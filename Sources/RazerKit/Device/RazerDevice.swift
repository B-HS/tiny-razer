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

    // MARK: - Firmware / serial

    public func readFirmwareVersion(via transport: HIDTransport) async throws -> String {
        let response = try await transport.request(stamp(MiscCommands.getFirmwareVersion()), from: handle)
        return MiscCommands.parseFirmwareVersion(response)
    }

    public func readSerialNumber(via transport: HIDTransport) async throws -> String {
        let response = try await transport.request(stamp(MiscCommands.getSerialNumber()), from: handle)
        return MiscCommands.parseSerialNumber(response)
    }

    // MARK: - DPI stages

    public func readDPIStages(via transport: HIDTransport) async throws -> MiscCommands.DPIStageList {
        let response = try await transport.request(stamp(MiscCommands.getDPIStages()), from: handle)
        return MiscCommands.parseDPIStages(response)
    }

    public func writeDPIStages(_ stages: [(x: UInt16, y: UInt16)], activeStage: UInt8,
                                via transport: HIDTransport) async throws {
        try await transport.send(stamp(MiscCommands.setDPIStages(stages, activeStage: activeStage)), to: handle)
    }

    // MARK: - Idle / low battery

    public func readIdleTime(via transport: HIDTransport) async throws -> UInt16 {
        let response = try await transport.request(stamp(MiscCommands.getIdleTime()), from: handle)
        return MiscCommands.parseIdleTime(response)
    }

    public func writeIdleTime(seconds: UInt16, via transport: HIDTransport) async throws {
        try await transport.send(stamp(MiscCommands.setIdleTime(seconds: seconds)), to: handle)
    }

    public func readLowBatteryThreshold(via transport: HIDTransport) async throws -> Int {
        let response = try await transport.request(stamp(MiscCommands.getLowBatteryThreshold()), from: handle)
        return MiscCommands.parseLowBatteryThreshold(response)
    }

    public func writeLowBatteryThreshold(percent: Int, via transport: HIDTransport) async throws {
        try await transport.send(stamp(MiscCommands.setLowBatteryThreshold(percent: percent)), to: handle)
    }

    // MARK: - Brightness (main zone)

    public func readBrightness(via transport: HIDTransport) async throws -> UInt8 {
        let cmd = descriptor.capabilities.contains(.extendedEffects)
            ? LEDExtendedCommands.getBrightness(zone: .matrix)
            : LEDStandardCommands.getLEDBrightness(zone: .backlight)
        let response = try await transport.request(stamp(cmd), from: handle)
        return descriptor.capabilities.contains(.extendedEffects)
            ? LEDExtendedCommands.parseBrightness(response)
            : LEDStandardCommands.parseLEDBrightness(response)
    }

    public func writeBrightness(_ value: UInt8, via transport: HIDTransport) async throws {
        let cmd = descriptor.capabilities.contains(.extendedEffects)
            ? LEDExtendedCommands.setBrightness(zone: .matrix, value: value)
            : LEDStandardCommands.setLEDBrightness(zone: .backlight, value: value)
        try await transport.send(stamp(cmd), to: handle)
    }

    // MARK: - LED effects (main zone)

    public func writeLEDEffect(_ effect: LEDEffect, via transport: HIDTransport) async throws {
        let extended = descriptor.capabilities.contains(.extendedEffects)
        let cmd: RazerReport
        switch effect {
        case .off:
            cmd = extended
                ? LEDExtendedCommands.effectNone(zone: .matrix)
                : LEDStandardCommands.matrixEffectNone()
        case .static(let color):
            cmd = extended
                ? LEDExtendedCommands.effectStatic(zone: .matrix, color: color)
                : LEDStandardCommands.matrixEffectStatic(color: color)
        case .spectrum:
            cmd = extended
                ? LEDExtendedCommands.effectSpectrum(zone: .matrix)
                : LEDStandardCommands.matrixEffectSpectrum()
        case .wave(let direction):
            cmd = extended
                ? LEDExtendedCommands.effectWave(zone: .matrix, direction: direction)
                : LEDStandardCommands.matrixEffectWave(direction: direction)
        case let .reactive(speed, color):
            cmd = extended
                ? LEDExtendedCommands.effectReactive(zone: .matrix, speed: speed, color: color)
                : LEDStandardCommands.matrixEffectReactive(speed: speed, color: color)
        case .breathingSingle(let color):
            cmd = extended
                ? LEDExtendedCommands.effectBreathingSingle(zone: .matrix, color: color)
                : LEDStandardCommands.matrixEffectBreathingSingle(color: color)
        case let .breathingDual(a, b):
            cmd = extended
                ? LEDExtendedCommands.effectBreathingDual(zone: .matrix, color1: a, color2: b)
                : LEDStandardCommands.matrixEffectBreathingDual(color1: a, color2: b)
        case .breathingRandom:
            cmd = extended
                ? LEDExtendedCommands.effectBreathingRandom(zone: .matrix)
                : LEDStandardCommands.matrixEffectBreathingRandom()
        case let .starlightSingle(speed, color):
            cmd = extended
                ? LEDExtendedCommands.effectStarlightSingle(zone: .matrix, speed: speed, color: color)
                : LEDStandardCommands.matrixEffectStarlightSingle(speed: speed, color: color)
        case let .starlightDual(speed, a, b):
            cmd = extended
                ? LEDExtendedCommands.effectStarlightDual(zone: .matrix, speed: speed, color1: a, color2: b)
                : LEDStandardCommands.matrixEffectStarlightDual(speed: speed, color1: a, color2: b)
        case .starlightRandom(let speed):
            cmd = extended
                ? LEDExtendedCommands.effectStarlightRandom(zone: .matrix, speed: speed)
                : LEDStandardCommands.matrixEffectStarlightRandom(speed: speed)
        }
        try await transport.send(stamp(cmd), to: handle)
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

/// High-level lighting effect the UI can request. Maps to either the classic
/// or the extended command family depending on the device's capabilities.
public enum LEDEffect: Sendable, Hashable {
    case off
    case `static`(RazerRGB)
    case spectrum
    case wave(WaveDirection)
    case reactive(speed: EffectSpeed, color: RazerRGB)
    case breathingSingle(RazerRGB)
    case breathingDual(RazerRGB, RazerRGB)
    case breathingRandom
    case starlightSingle(speed: EffectSpeed, color: RazerRGB)
    case starlightDual(speed: EffectSpeed, RazerRGB, RazerRGB)
    case starlightRandom(speed: EffectSpeed)
}

extension RazerDevice {
    /// Promote a raw HID handle into a `RazerDevice` if we recognise its PID.
    public static func from(handle: HIDDeviceHandle) -> RazerDevice? {
        guard handle.vendorID == RazerKit.vendorID else { return nil }
        guard let descriptor = DeviceCatalog.descriptor(for: handle.productID) else { return nil }
        return RazerDevice(handle: handle, descriptor: descriptor)
    }
}
