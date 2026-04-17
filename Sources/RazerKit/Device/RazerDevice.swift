import Foundation

/// A concrete Razer device: a pairing of a `HIDDeviceHandle` with a
/// `DeviceDescriptor`. The transport stays in `RazerKit` and is injected so
/// features can issue commands without knowing about IOKit.
public struct RazerDevice: Sendable, Identifiable, Equatable {
    public let handle: HIDDeviceHandle
    public let descriptor: DeviceDescriptor

    public var id: UInt64 { handle.id }
    public var displayName: String { descriptor.displayName }
    public var category: DeviceCategory { descriptor.category }

    public init(handle: HIDDeviceHandle, descriptor: DeviceDescriptor) {
        self.handle = handle
        self.descriptor = descriptor
    }

    public func supports(_ capability: Capability) -> Bool {
        descriptor.capabilities.contains(capability)
    }

    // MARK: - DPI

    public func readDPI(via transport: HIDTransport) async throws -> (x: UInt16, y: UInt16) {
        let response = try await transport.request(stamp(MiscCommands.getDPI()), from: handle)
        return MiscCommands.parseDPI(response)
    }

    public func writeDPI(x: UInt16, y: UInt16, via transport: HIDTransport) async throws {
        try await transport.send(stamp(MiscCommands.setDPI(x: x, y: y)), to: handle)
    }

    // MARK: - Polling rate

    public func readPollingRate(via transport: HIDTransport) async throws -> PollingRate? {
        let useHyper = descriptor.capabilities.contains(.pollingRateHyper)
        let cmd = useHyper ? MiscCommands.getPollingRate2() : MiscCommands.getPollingRate()
        let response = try await transport.request(stamp(cmd), from: handle)
        return useHyper ? MiscCommands.parsePollingRate2(response) : MiscCommands.parsePollingRate(response)
    }

    public func writePollingRate(_ rate: PollingRate, via transport: HIDTransport) async throws {
        let isHyper = descriptor.hyperPollingRates.contains(rate)
        let cmd = isHyper
            ? MiscCommands.setPollingRate2(rate)
            : MiscCommands.setPollingRate(rate)
        try await transport.send(stamp(cmd), to: handle)
    }

    // MARK: - Battery

    public func readBatteryPercent(via transport: HIDTransport) async throws -> Int {
        let response = try await transport.request(stamp(MiscCommands.getBatteryLevel()), from: handle)
        return MiscCommands.parseBatteryLevel(response)
    }

    public func readIsCharging(via transport: HIDTransport) async throws -> Bool {
        let response = try await transport.request(stamp(MiscCommands.getChargingStatus()), from: handle)
        return MiscCommands.parseChargingStatus(response)
    }

    // MARK: - Private

    /// Stamps the device's required `transaction_id` onto a command report
    /// before it goes on the wire.
    private func stamp(_ report: RazerReport) -> RazerReport {
        var copy = report
        copy.transactionID = descriptor.transactionID
        return copy
    }
}

extension RazerDevice {
    /// Promote a raw HID handle into a `RazerDevice` if we recognise its PID.
    public static func from(handle: HIDDeviceHandle) -> RazerDevice? {
        guard handle.vendorID == RazerKit.vendorID else { return nil }
        guard let descriptor = DeviceCatalog.descriptor(for: handle.productID) else { return nil }
        return RazerDevice(handle: handle, descriptor: descriptor)
    }
}
