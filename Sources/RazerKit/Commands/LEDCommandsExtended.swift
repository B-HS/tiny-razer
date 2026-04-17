import Foundation

/// Extended matrix effect commands. Ported from
/// openrazer/driver/razerchromacommon.c `razer_chroma_extended_matrix_effect_*`.
/// Used by modern multi-zone devices (BlackWidow V3+, DeathAdder V2+, etc.).
///
/// All commands take a variable-storage flag and an LED zone; effect layout
/// shares a common header (`varstore + zone + effect_id`) followed by
/// effect-specific parameters.
public enum LEDExtendedCommands {
    // MARK: - Effect commands (command_class 0x0F, command_id 0x02)

    public static func effectNone(
        zone: LEDZone,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        base(argSize: 0x06, store: store, zone: zone, effectID: 0x00)
    }

    public static func effectStatic(
        zone: LEDZone,
        color: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x09, store: store, zone: zone, effectID: 0x01)
        r.setArgument(0x01, at: 5)
        r.setArgument(color.r, at: 6)
        r.setArgument(color.g, at: 7)
        r.setArgument(color.b, at: 8)
        return r
    }

    public static func effectBreathingRandom(
        zone: LEDZone,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        base(argSize: 0x06, store: store, zone: zone, effectID: 0x02)
    }

    public static func effectBreathingSingle(
        zone: LEDZone,
        color: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x09, store: store, zone: zone, effectID: 0x02)
        r.setArgument(0x01, at: 3)
        r.setArgument(0x01, at: 5)
        r.setArgument(color.r, at: 6)
        r.setArgument(color.g, at: 7)
        r.setArgument(color.b, at: 8)
        return r
    }

    public static func effectBreathingDual(
        zone: LEDZone,
        color1: RazerRGB,
        color2: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x0C, store: store, zone: zone, effectID: 0x02)
        r.setArgument(0x02, at: 3)
        r.setArgument(0x02, at: 5)
        r.setArgument(color1.r, at: 6)
        r.setArgument(color1.g, at: 7)
        r.setArgument(color1.b, at: 8)
        r.setArgument(color2.r, at: 9)
        r.setArgument(color2.g, at: 10)
        r.setArgument(color2.b, at: 11)
        return r
    }

    public static func effectSpectrum(
        zone: LEDZone,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        base(argSize: 0x06, store: store, zone: zone, effectID: 0x03)
    }

    public static func effectWave(
        zone: LEDZone,
        direction: WaveDirection,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x06, store: store, zone: zone, effectID: 0x04)
        r.setArgument(direction.rawValue, at: 3)
        r.setArgument(0x28, at: 4)  // default speed; lower = faster
        return r
    }

    public static func effectReactive(
        zone: LEDZone,
        speed: EffectSpeed,
        color: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x09, store: store, zone: zone, effectID: 0x05)
        r.setArgument(clamp(speed.rawValue, 1, 4), at: 4)
        r.setArgument(0x01, at: 5)
        r.setArgument(color.r, at: 6)
        r.setArgument(color.g, at: 7)
        r.setArgument(color.b, at: 8)
        return r
    }

    public static func effectStarlightRandom(
        zone: LEDZone,
        speed: EffectSpeed,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x06, store: store, zone: zone, effectID: 0x07)
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 4)
        return r
    }

    public static func effectStarlightSingle(
        zone: LEDZone,
        speed: EffectSpeed,
        color: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x09, store: store, zone: zone, effectID: 0x07)
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 4)
        r.setArgument(0x01, at: 5)
        r.setArgument(color.r, at: 6)
        r.setArgument(color.g, at: 7)
        r.setArgument(color.b, at: 8)
        return r
    }

    public static func effectStarlightDual(
        zone: LEDZone,
        speed: EffectSpeed,
        color1: RazerRGB,
        color2: RazerRGB,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = base(argSize: 0x0C, store: store, zone: zone, effectID: 0x07)
        r.setArgument(clamp(speed.rawValue, 1, 3), at: 4)
        r.setArgument(0x02, at: 5)
        r.setArgument(color1.r, at: 6)
        r.setArgument(color1.g, at: 7)
        r.setArgument(color1.b, at: 8)
        r.setArgument(color2.r, at: 9)
        r.setArgument(color2.g, at: 10)
        r.setArgument(color2.b, at: 11)
        return r
    }

    // MARK: - Brightness (class 0x0F, id 0x04)

    public static func setBrightness(
        zone: LEDZone,
        value: UInt8,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x0F,
            commandID: CommandID(direction: .set, id: 0x04),
            dataSize: 0x03
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        r.setArgument(value, at: 2)
        return r
    }

    public static func getBrightness(
        zone: LEDZone,
        store: UInt8 = MiscCommands.varStore
    ) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x0F,
            commandID: CommandID(direction: .get, id: 0x04),
            dataSize: 0x03
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        return r
    }

    public static func parseBrightness(_ response: RazerReport) -> UInt8 {
        response.argument(at: 2)
    }

    // MARK: - Private helpers

    private static func base(argSize: UInt8, store: UInt8, zone: LEDZone, effectID: UInt8) -> RazerReport {
        var r = RazerReport(
            commandClass: 0x0F,
            commandID: CommandID(direction: .set, id: 0x02),
            dataSize: argSize
        )
        r.setArgument(store, at: 0)
        r.setArgument(zone.rawValue, at: 1)
        r.setArgument(effectID, at: 2)
        return r
    }

    private static func clamp(_ v: UInt8, _ lo: UInt8, _ hi: UInt8) -> UInt8 {
        min(max(v, lo), hi)
    }
}
