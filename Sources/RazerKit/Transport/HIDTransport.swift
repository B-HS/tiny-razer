import Foundation
import os
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

private let log = Logger(subsystem: "com.hyunseokbyun.tinyrazer", category: "HIDTransport")

/// IOKit-backed Razer HID transport.
///
/// Runs an `IOHIDManager` on a dedicated dispatch queue, exposes device
/// connect/disconnect as an `AsyncStream`, and speaks the Razer feature-report
/// protocol (90-byte reports at `wValue = 0x300`).
public actor HIDTransport {
    public struct DeviceEvent: Sendable {
        public enum Kind: Sendable { case connected, disconnected }
        public let kind: Kind
        public let handle: HIDDeviceHandle
    }

    public nonisolated let vendorID: Int

    private let manager: IOHIDManager
    private let queue: DispatchQueue
    private let registry: DeviceRegistry
    private var isStarted = false
    private var eventContinuation: AsyncStream<DeviceEvent>.Continuation?
    private var openedDevices: Set<IOHIDDevice> = []

    /// Default wait between SetReport (request) and GetReport (response) in
    /// the Razer control flow. Matches openrazer's typical wait_min.
    public static let defaultResponseDelay: Duration = .milliseconds(3)

    public init(vendorID: Int = RazerKit.vendorID) {
        self.vendorID = vendorID
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.queue = DispatchQueue(label: "tiny-razer.hid-transport", qos: .userInitiated)
        self.registry = DeviceRegistry()
    }

    // MARK: - Lifecycle

    /// Begin matching Razer devices and emit `DeviceEvent`s on the returned stream.
    ///
    /// The continuation and the registry emitter are both installed *before*
    /// `IOHIDManagerActivate` so matching callbacks that fire at activation
    /// time are not dropped.
    public func start() throws -> AsyncStream<DeviceEvent> {
        if isStarted {
            return makeExistingStream()
        }

        log.info("Starting IOHIDManager for vendorID 0x\(String(self.vendorID, radix: 16), privacy: .public)")

        // 1. Make & install the continuation synchronously on the actor.
        let (stream, continuation) = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .unbounded)
        self.eventContinuation = continuation
        registry.setEmitter { event in
            continuation.yield(event)
        }

        // 2. Configure matching before callbacks can fire.
        let matching: [String: Any] = [kIOHIDVendorIDKey: vendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerSetDispatchQueue(manager, queue)

        // 3. Register callbacks with the registry as their context pointer.
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                let registry = Unmanaged<DeviceRegistry>.fromOpaque(context).takeUnretainedValue()
                registry.handleMatched(device)
            },
            Unmanaged.passUnretained(registry).toOpaque()
        )

        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                let registry = Unmanaged<DeviceRegistry>.fromOpaque(context).takeUnretainedValue()
                registry.handleRemoved(device)
            },
            Unmanaged.passUnretained(registry).toOpaque()
        )

        // 4. Activate. With the dispatch queue API, IOHIDManagerOpen is not
        //    required and actually fails with kIOReturnNotPermitted on modern
        //    macOS unless the app has the Input Monitoring TCC permission.
        //    Matching + feature-report I/O work without it.
        IOHIDManagerActivate(manager)
        isStarted = true
        log.info("IOHIDManager activated (no Open — relying on dispatch queue + matching)")
        return stream
    }

    public func stop() {
        guard isStarted else { return }
        for device in openedDevices {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        openedDevices.removeAll()
        IOHIDManagerCancel(manager)
        isStarted = false
        eventContinuation?.finish()
        eventContinuation = nil
        registry.reset()
    }

    /// Snapshot of currently-connected devices.
    public func currentDevices() -> [HIDDeviceHandle] {
        registry.allHandles()
    }

    // MARK: - I/O

    /// Send a report to a device (SetReport, Feature type, reportID = 0).
    public func send(_ report: RazerReport, to device: HIDDeviceHandle) throws {
        guard isStarted else { throw TransportError.transportNotStarted }
        guard let ioDevice = registry.ioDevice(for: device.id) else {
            throw TransportError.deviceNotConnected
        }
        let finalized = report.finalized()
        do {
            try setFeatureReport(finalized, on: ioDevice)
        } catch {
            for fallback in registry.fallbackDevices(for: device.id) {
                do {
                    try setFeatureReport(finalized, on: fallback)
                    return
                } catch {
                    continue
                }
            }
            throw error
        }
    }

    /// Send a request (SetReport) and read back the response (GetReport).
    public func request(
        _ report: RazerReport,
        from device: HIDDeviceHandle,
        delay: Duration = defaultResponseDelay
    ) async throws -> RazerReport {
        guard isStarted else { throw TransportError.transportNotStarted }
        guard let ioDevice = registry.ioDevice(for: device.id) else {
            throw TransportError.deviceNotConnected
        }

        let finalized = report.finalized()
        let candidates = [ioDevice] + registry.fallbackDevices(for: device.id)
        var lastError: Error?
        for candidate in candidates {
            do {
                try setFeatureReport(finalized, on: candidate)
                try? await Task.sleep(for: delay)
                let response = try getFeatureReport(on: candidate)
                let head = response.toBytes().prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
                let usage = IOHIDDeviceGetProperty(candidate, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                log.info("RX cls=0x\(String(finalized.commandClass, radix: 16), privacy: .public) id=0x\(String(finalized.commandID.rawValue, radix: 16), privacy: .public) usage=\(usage, privacy: .public) status=\(response.status.rawValue, privacy: .public) head=[\(head, privacy: .public)]")

                // status == .successful → take it.
                // status == .new (0x00) → device didn't process this report; typical when we
                // hit the wrong HID collection (e.g. keyboard instead of mouse). Try the next
                // candidate.
                if response.status == .successful {
                    registry.promotePrimary(device.id, to: candidate)
                    return response
                }
                if response.status == .new {
                    log.info("Status=new on usage=\(usage, privacy: .public); trying next collection")
                    lastError = TransportError.reportStatus(.new)
                    continue
                }
                lastError = TransportError.reportStatus(response.status)
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? TransportError.timeout
    }

    // MARK: - Private

    private func makeExistingStream() -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    private func setFeatureReport(_ report: RazerReport, on device: IOHIDDevice) throws {
        try ensureDeviceOpen(device)
        var bytes = report.toBytes()
        let result = bytes.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                0x00,
                buffer.baseAddress!,
                buffer.count
            )
        }
        if result != kIOReturnSuccess {
            let hex = String(UInt32(bitPattern: result), radix: 16, uppercase: true)
            log.error("IOHIDDeviceSetReport failed: 0x\(hex, privacy: .public)")
            throw TransportError.ioKitError(result)
        }
    }

    private func getFeatureReport(on device: IOHIDDevice) throws -> RazerReport {
        try ensureDeviceOpen(device)
        var bytes = [UInt8](repeating: 0, count: RazerReport.byteCount)
        var length = CFIndex(RazerReport.byteCount)
        let result = bytes.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                0x00,
                buffer.baseAddress!,
                &length
            )
        }
        if result != kIOReturnSuccess {
            let hex = String(UInt32(bitPattern: result), radix: 16, uppercase: true)
            log.error("IOHIDDeviceGetReport failed: 0x\(hex, privacy: .public)")
            throw TransportError.ioKitError(result)
        }
        guard length == RazerReport.byteCount, let report = RazerReport(bytes: bytes) else {
            throw TransportError.invalidResponseLength(Int(length))
        }
        return report
    }

    /// Ensures the HID device is opened (non-seize) so feature reports can
    /// flow. We remember the set of devices we've successfully opened so each
    /// call is a no-op after the first.
    private func ensureDeviceOpen(_ device: IOHIDDevice) throws {
        if openedDevices.contains(device) { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            openedDevices.insert(device)
            log.info("IOHIDDeviceOpen success for PID=0x\(String(IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0, radix: 16), privacy: .public) usage=\(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0, privacy: .public)")
            return
        }
        let hex = String(UInt32(bitPattern: result), radix: 16, uppercase: true)
        log.error("IOHIDDeviceOpen failed: 0x\(hex, privacy: .public)")
        throw TransportError.ioKitError(result)
    }
}

// MARK: - Device registry

/// Maintains the IOHIDDevice ↔ HIDDeviceHandle mapping behind a lock so it can
/// be touched from IOKit callback threads.
final class DeviceRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var byID: [UInt64: Entry] = [:]
    private var ioDeviceToID: [IOHIDDevice: UInt64] = [:]
    private var byDedupeKey: [String: UInt64] = [:]
    private var nextID: UInt64 = 1
    private var emitter: (@Sendable (HIDTransport.DeviceEvent) -> Void)?

    struct Entry {
        let handle: HIDDeviceHandle
        let ioDevice: IOHIDDevice
        var fallbackDevices: [IOHIDDevice]
        let usagePage: Int
    }

    func setEmitter(_ emitter: @escaping @Sendable (HIDTransport.DeviceEvent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.emitter = emitter
    }

    func handleMatched(_ device: IOHIDDevice) {
        lock.lock()
        if ioDeviceToID[device] != nil {
            lock.unlock()
            return
        }

        let productID = Self.intProperty(device, kIOHIDProductIDKey) ?? 0
        let serial = Self.stringProperty(device, kIOHIDSerialNumberKey) ?? ""
        let locationID = Self.intProperty(device, kIOHIDLocationIDKey) ?? 0
        let usagePage = Self.intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = Self.intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        let name = Self.stringProperty(device, kIOHIDProductKey) ?? "?"

        log.info("HID match: PID=0x\(String(productID, radix: 16)) '\(name)' usage=\(usagePage, privacy: .public)/\(usage, privacy: .public) loc=0x\(String(locationID, radix: 16))")

        // Dedupe: multiple HID collections on the same physical device share
        // serial (or location when serial is absent). Prefer the vendor-specific
        // collection (usage page ≥ 0xFF00) since that's where Razer's control
        // interface lives; otherwise keep the first one we see.
        let dedupeKey = serial.isEmpty ? "loc-\(productID)-\(locationID)" : "sn-\(productID)-\(serial)"
        let isVendorCollection = usagePage >= 0xFF00
        let existingIDForKey = byDedupeKey[dedupeKey]

        if let existingID = existingIDForKey {
            let existingUsagePage = byID[existingID]?.usagePage ?? 0
            let existingIsVendor = existingUsagePage >= 0xFF00
            if !isVendorCollection || existingIsVendor {
                // Keep the existing primary; record this collection as a fallback.
                byID[existingID]?.fallbackDevices.append(device)
                ioDeviceToID[device] = existingID
                lock.unlock()
                return
            }
            // New collection is vendor-specific; promote it to primary.
            if let existingEntry = byID[existingID] {
                let updatedEntry = Entry(
                    handle: Self.makeHandle(id: existingID, device: device),
                    ioDevice: device,
                    fallbackDevices: [existingEntry.ioDevice] + existingEntry.fallbackDevices,
                    usagePage: usagePage
                )
                byID[existingID] = updatedEntry
                ioDeviceToID[device] = existingID
            }
            lock.unlock()
            return
        }

        let id = nextID
        nextID += 1
        let handle = Self.makeHandle(id: id, device: device)
        byID[id] = Entry(handle: handle, ioDevice: device, fallbackDevices: [], usagePage: usagePage)
        ioDeviceToID[device] = id
        byDedupeKey[dedupeKey] = id
        let emitter = self.emitter
        lock.unlock()
        emitter?(.init(kind: .connected, handle: handle))
    }

    func handleRemoved(_ device: IOHIDDevice) {
        lock.lock()
        guard let id = ioDeviceToID.removeValue(forKey: device) else {
            lock.unlock()
            return
        }
        guard var entry = byID[id] else {
            lock.unlock()
            return
        }

        // If the removed IOHIDDevice was a fallback, just drop it from the list.
        if entry.ioDevice != device {
            entry.fallbackDevices.removeAll { $0 == device }
            byID[id] = entry
            lock.unlock()
            return
        }

        // Primary removed — promote a fallback if any remain.
        if !entry.fallbackDevices.isEmpty {
            let next = entry.fallbackDevices.removeFirst()
            let usagePage = Self.intProperty(next, kIOHIDPrimaryUsagePageKey) ?? 0
            let newEntry = Entry(
                handle: Self.makeHandle(id: id, device: next),
                ioDevice: next,
                fallbackDevices: entry.fallbackDevices,
                usagePage: usagePage
            )
            byID[id] = newEntry
            lock.unlock()
            return
        }

        byID.removeValue(forKey: id)
        byDedupeKey = byDedupeKey.filter { $0.value != id }
        let emitter = self.emitter
        lock.unlock()
        emitter?(.init(kind: .disconnected, handle: entry.handle))
    }

    func ioDevice(for id: UInt64) -> IOHIDDevice? {
        lock.lock()
        defer { lock.unlock() }
        return byID[id]?.ioDevice
    }

    func allHandles() -> [HIDDeviceHandle] {
        lock.lock()
        defer { lock.unlock() }
        return byID.values.map(\.handle)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        byID.removeAll()
        ioDeviceToID.removeAll()
        byDedupeKey.removeAll()
        emitter = nil
    }

    func fallbackDevices(for id: UInt64) -> [IOHIDDevice] {
        lock.lock()
        defer { lock.unlock() }
        return byID[id]?.fallbackDevices ?? []
    }

    /// Move `newPrimary` to the primary slot for `id`. Called once we discover
    /// (empirically) which HID collection actually services the Razer control
    /// protocol. Subsequent requests then hit the right one on the first try.
    func promotePrimary(_ id: UInt64, to newPrimary: IOHIDDevice) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = byID[id], entry.ioDevice != newPrimary else { return }
        var fallbacks = entry.fallbackDevices
        fallbacks.removeAll { $0 == newPrimary }
        fallbacks.append(entry.ioDevice)
        let usagePage = Self.intProperty(newPrimary, kIOHIDPrimaryUsagePageKey) ?? 0
        entry = Entry(
            handle: entry.handle,
            ioDevice: newPrimary,
            fallbackDevices: fallbacks,
            usagePage: usagePage
        )
        byID[id] = entry
    }

    // MARK: - Handle construction

    private static func makeHandle(id: UInt64, device: IOHIDDevice) -> HIDDeviceHandle {
        HIDDeviceHandle(
            id: id,
            vendorID: intProperty(device, kIOHIDVendorIDKey) ?? 0,
            productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
            name: stringProperty(device, kIOHIDProductKey) ?? "Unknown",
            serialNumber: stringProperty(device, kIOHIDSerialNumberKey),
            manufacturer: stringProperty(device, kIOHIDManufacturerKey),
            usagePage: intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            usage: intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        )
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        guard let raw = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return raw as? String
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        guard let raw = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return (raw as? NSNumber)?.intValue
    }
}
