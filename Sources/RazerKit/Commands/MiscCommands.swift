import Foundation

/// Subset of `razer_chroma_misc_*` builders from
/// openrazer/driver/razerchromacommon.c needed for mouse devices
/// (DeathAdder V3 Pro and similar).
public enum MiscCommands {
    public static let noStore: UInt8 = 0x00
    public static let varStore: UInt8 = 0x01

    // MARK: - DPI

    /// Set DPI (X, Y) using the 16-bit command.
    ///
    /// Source: razer_chroma_misc_set_dpi_xy, razerchromacommon.c:1211.
    /// Upstream hardcodes VARSTORE into arg[0] regardless of the parameter; we
    /// expose the flag honestly so callers can pick.
    public static func setDPI(x: UInt16, y: UInt16, store: UInt8 = varStore) -> RazerReport {
        let clampedX = min(max(x, 100), 45_000)
        let clampedY = min(max(y, 100), 45_000)
        var report = RazerReport(
            commandClass: 0x04,
            commandID: CommandID(direction: .set, id: 0x05),
            dataSize: 0x07
        )
        report.setArgument(store, at: 0)
        report.setArgument(UInt8(truncatingIfNeeded: clampedX >> 8), at: 1)
        report.setArgument(UInt8(truncatingIfNeeded: clampedX), at: 2)
        report.setArgument(UInt8(truncatingIfNeeded: clampedY >> 8), at: 3)
        report.setArgument(UInt8(truncatingIfNeeded: clampedY), at: 4)
        return report
    }

    /// Read current DPI (X, Y).
    ///
    /// Source: razer_chroma_misc_get_dpi_xy, razerchromacommon.c:1234.
    public static func getDPI(store: UInt8 = varStore) -> RazerReport {
        var report = RazerReport(
            commandClass: 0x04,
            commandID: CommandID(direction: .get, id: 0x05),
            dataSize: 0x07
        )
        report.setArgument(store, at: 0)
        return report
    }

    /// Decode a DPI response report.
    public static func parseDPI(_ response: RazerReport) -> (x: UInt16, y: UInt16) {
        let xHi = UInt16(response.argument(at: 1))
        let xLo = UInt16(response.argument(at: 2))
        let yHi = UInt16(response.argument(at: 3))
        let yLo = UInt16(response.argument(at: 4))
        return ((xHi << 8) | xLo, (yHi << 8) | yLo)
    }

    // MARK: - Polling rate (classic, ≤1000 Hz)

    /// Set polling rate. Supported: 1000, 500, 125 Hz.
    ///
    /// Source: razer_chroma_misc_set_polling_rate, razerchromacommon.c:1104.
    public static func setPollingRate(_ rate: PollingRate) -> RazerReport {
        var report = RazerReport(
            commandClass: 0x00,
            commandID: CommandID(direction: .set, id: 0x05),
            dataSize: 0x01
        )
        report.setArgument(rate.classicCode, at: 0)
        return report
    }

    /// Read current polling rate.
    ///
    /// Source: razer_chroma_misc_get_polling_rate, razerchromacommon.c:1092.
    public static func getPollingRate() -> RazerReport {
        RazerReport(
            commandClass: 0x00,
            commandID: CommandID(direction: .get, id: 0x05),
            dataSize: 0x01
        )
    }

    /// Decode the classic `getPollingRate` response byte (arg[0]).
    public static func parsePollingRate(_ response: RazerReport) -> PollingRate? {
        switch response.argument(at: 0) {
        case 0x01: return .hz1000
        case 0x02: return .hz500
        case 0x08: return .hz125
        default: return nil
        }
    }

    /// Decode the hyper `getPollingRate2` response byte (arg[1]).
    public static func parsePollingRate2(_ response: RazerReport) -> PollingRate? {
        switch response.argument(at: 1) {
        case 0x01: return .hz8000
        case 0x02: return .hz4000
        case 0x04: return .hz2000
        case 0x08: return .hz1000
        case 0x10: return .hz500
        case 0x40: return .hz125
        default: return nil
        }
    }

    // MARK: - Polling rate 2 (high-rate: up to 8000 Hz)

    /// Set polling rate for HyperPolling-capable devices (up to 8000 Hz).
    ///
    /// Source: razer_chroma_misc_set_polling_rate2, razerchromacommon.c:1153.
    public static func setPollingRate2(_ rate: PollingRate, argument: UInt8 = 0x00) -> RazerReport {
        var report = RazerReport(
            commandClass: 0x00,
            commandID: CommandID(direction: .set, id: 0x40),
            dataSize: 0x02
        )
        report.setArgument(argument, at: 0)
        report.setArgument(rate.hyperCode, at: 1)
        return report
    }

    /// Read polling rate for HyperPolling devices.
    public static func getPollingRate2() -> RazerReport {
        RazerReport(
            commandClass: 0x00,
            commandID: CommandID(direction: .get, id: 0x40),
            dataSize: 0x01
        )
    }

    // MARK: - Battery / charging

    /// Read battery charge level (0-255, treated as 0-100%).
    ///
    /// Source: razer_chroma_misc_get_battery_level, razerchromacommon.c:1057.
    public static func getBatteryLevel() -> RazerReport {
        RazerReport(
            commandClass: 0x07,
            commandID: CommandID(direction: .get, id: 0x80),
            dataSize: 0x02
        )
    }

    /// Decode battery level from response — percent in 0...100.
    public static func parseBatteryLevel(_ response: RazerReport) -> Int {
        let raw = Int(response.argument(at: 1))
        return Int((Double(raw) / 255.0 * 100.0).rounded())
    }

    /// Read charging status (0 = not charging, 1 = charging).
    ///
    /// Source: razer_chroma_misc_get_charging_status, razerchromacommon.c:1067.
    public static func getChargingStatus() -> RazerReport {
        RazerReport(
            commandClass: 0x07,
            commandID: CommandID(direction: .get, id: 0x84),
            dataSize: 0x02
        )
    }

    public static func parseChargingStatus(_ response: RazerReport) -> Bool {
        response.argument(at: 1) != 0
    }
}

public enum PollingRate: Int, CaseIterable, Sendable {
    case hz125 = 125
    case hz500 = 500
    case hz1000 = 1000
    case hz2000 = 2000
    case hz4000 = 4000
    case hz8000 = 8000

    /// Classic set_polling_rate encoding (razerchromacommon.c:1108).
    var classicCode: UInt8 {
        switch self {
        case .hz1000: return 0x01
        case .hz500: return 0x02
        case .hz125: return 0x08
        default: return 0x02
        }
    }

    /// set_polling_rate2 encoding (razerchromacommon.c:1158).
    var hyperCode: UInt8 {
        switch self {
        case .hz8000: return 0x01
        case .hz4000: return 0x02
        case .hz2000: return 0x04
        case .hz1000: return 0x08
        case .hz500: return 0x10
        case .hz125: return 0x40
        }
    }
}
