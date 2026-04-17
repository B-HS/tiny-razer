import Foundation

/// Classic ("standard") matrix effect commands. Ported from
/// openrazer/driver/razerchromacommon.c `razer_chroma_standard_*`.
/// Used by older devices (BlackWidow Chroma, early DeathAdder Chroma, etc.).
/// Modern devices use the extended path — see `LEDCommandsExtended`.
public enum LEDStandardCommands {
    // MARK: - Matrix effects (command_class 0x03, command_id 0x0A)

    public static func matrixEffectNone() -> RazerReport {
        base(argSize: 0x01, effectID: 0x00)
    }

    public static func matrixEffectStatic(color: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x04, effectID: 0x06)
        r.setArgument(color.r, at: 1)
        r.setArgument(color.g, at: 2)
        r.setArgument(color.b, at: 3)
        return r
    }

    public static func matrixEffectSpectrum() -> RazerReport {
        base(argSize: 0x01, effectID: 0x04)
    }

    public static func matrixEffectWave(direction: WaveDirection) -> RazerReport {
        var r = base(argSize: 0x02, effectID: 0x01)
        r.setArgument(direction.rawValue, at: 1)
        return r
    }

    public static func matrixEffectReactive(speed: EffectSpeed, color: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x05, effectID: 0x02)
        r.setArgument(speed.rawValue, at: 1)
        r.setArgument(color.r, at: 2)
        r.setArgument(color.g, at: 3)
        r.setArgument(color.b, at: 4)
        return r
    }

    public static func matrixEffectBreathingSingle(color: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x08, effectID: 0x03)
        r.setArgument(0x01, at: 1) // breathing type = single
        r.setArgument(color.r, at: 2)
        r.setArgument(color.g, at: 3)
        r.setArgument(color.b, at: 4)
        return r
    }

    public static func matrixEffectBreathingDual(color1: RazerRGB, color2: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x08, effectID: 0x03)
        r.setArgument(0x02, at: 1)
        r.setArgument(color1.r, at: 2)
        r.setArgument(color1.g, at: 3)
        r.setArgument(color1.b, at: 4)
        r.setArgument(color2.r, at: 5)
        r.setArgument(color2.g, at: 6)
        r.setArgument(color2.b, at: 7)
        return r
    }

    public static func matrixEffectBreathingRandom() -> RazerReport {
        var r = base(argSize: 0x08, effectID: 0x03)
        r.setArgument(0x03, at: 1)
        return r
    }

    public static func matrixEffectStarlightSingle(speed: EffectSpeed, color: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x01, effectID: 0x19)
        r.setArgument(0x01, at: 1)                        // type: single
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 2)
        r.setArgument(color.r, at: 3)
        r.setArgument(color.g, at: 4)
        r.setArgument(color.b, at: 5)
        return r
    }

    public static func matrixEffectStarlightDual(speed: EffectSpeed, color1: RazerRGB, color2: RazerRGB) -> RazerReport {
        var r = base(argSize: 0x01, effectID: 0x19)
        r.setArgument(0x02, at: 1)
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 2)
        r.setArgument(color1.r, at: 3)
        r.setArgument(color1.g, at: 4)
        r.setArgument(color1.b, at: 5)
        r.setArgument(color2.r, at: 6)
        r.setArgument(color2.g, at: 7)
        r.setArgument(color2.b, at: 8)
        return r
    }

    public static func matrixEffectStarlightRandom(speed: EffectSpeed) -> RazerReport {
        var r = base(argSize: 0x01, effectID: 0x19)
        r.setArgument(0x03, at: 1)
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 2)
        return r
    }

    // MARK: - Per-LED state / color / brightness (command_class 0x03)

    public static func setLEDState(zone: LEDZone, on: Bool, store: UInt8 = MiscCommands.varStore) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x03,
            commandID: CommandID(direction: .set, id: 0x00),
            dataSize: 0x03
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        r.setArgument(on ? 0x01 : 0x00, at: 2)
        return r
    }

    public static func setLEDRGB(zone: LEDZone, color: RazerRGB, store: UInt8 = MiscCommands.varStore) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x03,
            commandID: CommandID(direction: .set, id: 0x01),
            dataSize: 0x05
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        r.setArgument(color.r, at: 2)
        r.setArgument(color.g, at: 3)
        r.setArgument(color.b, at: 4)
        return r
    }

    public static func setLEDBrightness(zone: LEDZone, value: UInt8, store: UInt8 = MiscCommands.varStore) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x03,
            commandID: CommandID(direction: .set, id: 0x03),
            dataSize: 0x03
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        r.setArgument(value, at: 2)
        return r
    }

    public static func getLEDBrightness(zone: LEDZone, store: UInt8 = MiscCommands.varStore) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x03,
            commandID: CommandID(direction: .get, id: 0x03),
            dataSize: 0x03
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        return r
    }

    public static func parseLEDBrightness(_ response: RazerReport) -> UInt8 {
        response.argument(at: 2)
    }

    // MARK: - Private helpers

    private static func base(argSize: UInt8, effectID: UInt8) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x03,
            commandID: CommandID(direction: .set, id: 0x0A),
            dataSize: argSize
        )
        r.setArgument(effectID, at: 0)
        return r
    }

    private static func clamp(_ v: UInt8, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
        min(max(v, lo), hi)
    }
}
