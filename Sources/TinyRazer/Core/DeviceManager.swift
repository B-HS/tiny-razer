import Foundation
import Observation
import RazerKit

@MainActor
@Observable
final class DeviceManager {
    private(set) var devices: [DeviceState] = []
    private(set) var isRunning: Bool = false
    private(set) var startupError: String?
    private(set) var needsInputMonitoringPermission: Bool = false

    private let transport: HIDTransport
    private var observerTask: Task<Void, Never>?
    private var pollingTasks: [UInt64: Task<Void, Never>] = [:]

    init(transport: HIDTransport = HIDTransport()) {
        self.transport = transport
    }

    func start() async {
        guard !isRunning else { return }
        do {
            let stream = try await transport.start()
            isRunning = true
            observerTask = Task { [weak self] in
                for await event in stream {
                    await self?.handle(event: event)
                }
            }
        } catch {
            startupError = (error as? TransportError)?.description ?? error.localizedDescription
            Log.manager.error("Transport failed to start: \(String(describing: error))")
        }
    }

    func stop() async {
        pollingTasks.values.forEach { $0.cancel() }
        pollingTasks.removeAll()
        observerTask?.cancel()
        observerTask = nil
        await transport.stop()
        devices = []
        isRunning = false
    }

    // MARK: - Event handling

    private func handle(event: HIDTransport.DeviceEvent) async {
        switch event.kind {
        case .connected:
            guard let device = RazerDevice.from(handle: event.handle) else {
                Log.manager.info("Ignoring unknown Razer PID 0x\(String(event.handle.productID, radix: 16))")
                return
            }
            if devices.contains(where: { $0.id == device.id }) { return }

            // Dedupe: a single physical device can appear via two PIDs at
            // once — e.g. DeathAdder V3 Pro plugged in by USB cable while
            // its wireless dongle is still attached. Treat same shortName +
            // category as the same mouse and prefer the wired variant.
            if let existingIndex = devices.firstIndex(where: {
                $0.device.descriptor.shortName == device.descriptor.shortName
                    && $0.device.category == device.category
            }) {
                let existing = devices[existingIndex].device
                let newIsWired = !device.descriptor.isWireless
                let existingIsWired = !existing.descriptor.isWireless
                if newIsWired && !existingIsWired {
                    Log.manager.info("Wired \(device.descriptor.shortName, privacy: .public) replaces wireless entry")
                    pollingTasks[existing.id]?.cancel()
                    pollingTasks.removeValue(forKey: existing.id)
                    devices.remove(at: existingIndex)
                } else {
                    Log.manager.info("Skipping duplicate \(device.descriptor.shortName, privacy: .public) (already tracked as \(existingIsWired ? "wired" : "wireless", privacy: .public))")
                    return
                }
            }

            var state = DeviceState(device: device)
            devices.append(state)
            state = await self.refreshState(state)
            if let index = devices.firstIndex(where: { $0.id == state.id }) {
                devices[index] = state
            }
            startPolling(for: state.id)

        case .disconnected:
            pollingTasks[event.handle.id]?.cancel()
            pollingTasks.removeValue(forKey: event.handle.id)
            devices.removeAll { $0.id == event.handle.id }

            // When the wired leg of a duplicate pair drops, an otherwise-
            // tracked wireless handle may have been suppressed by dedupe.
            // Re-scan what's actually on the HID bus and surface anything
            // missing from our list.
            await resurfaceSuppressedDevices()
        }
    }

    /// Add back any Razer device the transport still reports but that isn't
    /// currently in `devices`. Called after a disconnect in case dedupe had
    /// hidden a wireless counterpart.
    private func resurfaceSuppressedDevices() async {
        let handles = await transport.currentDevices()
        for handle in handles {
            guard let device = RazerDevice.from(handle: handle) else { continue }
            if devices.contains(where: { $0.id == device.id }) { continue }
            if devices.contains(where: {
                $0.device.descriptor.shortName == device.descriptor.shortName
                    && $0.device.category == device.category
            }) { continue }

            Log.manager.info("Resurfacing \(device.descriptor.shortName, privacy: .public) (\(device.descriptor.isWireless ? "wireless" : "wired", privacy: .public))")
            var state = DeviceState(device: device)
            devices.append(state)
            state = await refreshState(state)
            if let idx = devices.firstIndex(where: { $0.id == state.id }) {
                devices[idx] = state
            }
            startPolling(for: state.id)
        }
    }

    // MARK: - Actions

    func readStateNow(for id: UInt64) async {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let refreshed = await refreshState(devices[index])
        if let updatedIndex = devices.firstIndex(where: { $0.id == id }) {
            devices[updatedIndex] = refreshed
        }
    }

    func setDPI(x: UInt16, y: UInt16, for id: UInt64) async {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let device = devices[index].device
        do {
            try await device.writeDPI(x: x, y: y, via: transport)
            devices[index].dpiX = x
            devices[index].dpiY = y
            devices[index].lastError = nil
        } catch {
            devices[index].lastError = String(describing: error)
            noteError(error, action: "setDPI")
        }
    }

    func setPollingRate(_ rate: PollingRate, for id: UInt64) async {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let device = devices[index].device
        do {
            try await device.writePollingRate(rate, via: transport)
            devices[index].lastError = nil
        } catch {
            devices[index].lastError = String(describing: error)
            noteError(error, action: "setPollingRate")
        }
    }

    // MARK: - Polling

    private func startPolling(for id: UInt64) {
        pollingTasks[id]?.cancel()
        pollingTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                await self?.readStateNow(for: id)
            }
        }
    }

    private func refreshState(_ state: DeviceState) async -> DeviceState {
        var next = state
        let device = state.device
        Log.manager.info("refreshState for \(device.descriptor.shortName, privacy: .public) PID=0x\(String(device.handle.productID, radix: 16), privacy: .public)")

        if device.supports(.dpi) {
            do {
                let (x, y) = try await device.readDPI(via: transport)
                next.dpiX = x
                next.dpiY = y
                Log.manager.info("readDPI → \(x, privacy: .public)x\(y, privacy: .public)")
            } catch {
                noteError(error, action: "readDPI")
            }
        }

        if device.supports(.pollingRate) {
            do {
                if let rate = try await device.readPollingRate(via: transport) {
                    next.pollingRate = rate
                    Log.manager.info("readPollingRate → \(rate.rawValue, privacy: .public) Hz")
                }
            } catch {
                noteError(error, action: "readPollingRate")
            }
        }

        if device.supports(.battery) {
            do {
                let pct = try await device.readBatteryPercent(via: transport)
                next.batteryPercent = pct
                Log.manager.info("readBattery → \(pct, privacy: .public)%")
            } catch {
                noteError(error, action: "readBattery")
            }
        }

        if device.supports(.charging) {
            do {
                let charging = try await device.readIsCharging(via: transport)
                next.isCharging = charging
                Log.manager.info("readCharging → \(charging, privacy: .public)")
            } catch {
                noteError(error, action: "readCharging")
            }
        }

        return next
    }

    private func noteError(_ error: Error, action: String) {
        if let transportError = error as? TransportError, transportError.isPermissionDenied {
            needsInputMonitoringPermission = true
        }
        Log.manager.error("\(action) failed: \(String(describing: error))")
    }
}
