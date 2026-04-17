import Testing
@testable import RazerKit

@Suite("LED commands — classic")
struct LEDStandardCommandsTests {
    @Test("matrixEffectNone sets effect 0x00")
    func none() {
        let r = LEDStandardCommands.matrixEffectNone().finalized()
        let b = r.toBytes()
        #expect(b[6] == 0x03)  // class
        #expect(b[7] == 0x0A)  // command
        #expect(b[8] == 0x00)  // effect id = none
    }

    @Test("matrixEffectStatic writes RGB to args[1..3]")
    func staticColor() {
        let r = LEDStandardCommands.matrixEffectStatic(color: RazerRGB(r: 0xFF, g: 0x20, b: 0x40)).finalized()
        let b = r.toBytes()
        #expect(b[8] == 0x06)  // MATRIX_EFFECT_STATIC
        #expect(b[9] == 0xFF)
        #expect(b[10] == 0x20)
        #expect(b[11] == 0x40)
    }

    @Test("matrixEffectWave encodes direction at args[1]")
    func wave() {
        let left = LEDStandardCommands.matrixEffectWave(direction: .left).finalized()
        #expect(left.argument(at: 0) == 0x01) // MATRIX_EFFECT_WAVE
        #expect(left.argument(at: 1) == 0x01)
        let right = LEDStandardCommands.matrixEffectWave(direction: .right).finalized()
        #expect(right.argument(at: 1) == 0x02)
    }

    @Test("matrixEffectReactive clamps speed and carries color")
    func reactive() {
        let r = LEDStandardCommands.matrixEffectReactive(
            speed: .slow,
            color: RazerRGB(r: 0x11, g: 0x22, b: 0x33)
        ).finalized()
        #expect(r.argument(at: 0) == 0x02) // MATRIX_EFFECT_REACTIVE
        #expect(r.argument(at: 1) == 0x04) // slow
        #expect(r.argument(at: 2) == 0x11)
    }

    @Test("setLEDBrightness puts value at args[2]")
    func brightness() {
        let r = LEDStandardCommands.setLEDBrightness(zone: .backlight, value: 128).finalized()
        #expect(r.commandClass == 0x03)
        #expect(r.commandID.rawValue == 0x03)
        #expect(r.argument(at: 0) == 0x01) // VARSTORE
        #expect(r.argument(at: 1) == LEDZone.backlight.rawValue)
        #expect(r.argument(at: 2) == 128)
    }
}

@Suite("LED commands — extended")
struct LEDExtendedCommandsTests {
    @Test("effectStatic payload matches openrazer reference")
    func staticEffect() {
        // Reference (openrazer razerchromacommon.c:511 docstring):
        //   class 0x0F, cmd 0x02, data_size 0x09
        //   args: 01 05 01 00 00 01 FF 00 00  (VARSTR, Backlight, Static 0x01, ?, ?, 0x01, FF0000)
        let r = LEDExtendedCommands.effectStatic(
            zone: .backlight,
            color: RazerRGB(r: 0xFF, g: 0x00, b: 0x00)
        ).finalized()
        let b = r.toBytes()
        #expect(b[5] == 0x09)
        #expect(b[6] == 0x0F)
        #expect(b[7] == 0x02)
        #expect(b[8] == 0x01)  // VARSTORE
        #expect(b[9] == 0x05)  // backlight zone
        #expect(b[10] == 0x01) // effect static
        #expect(b[13] == 0x01) // colour count
        #expect(b[14] == 0xFF)
        #expect(b[15] == 0x00)
        #expect(b[16] == 0x00)
    }

    @Test("effectSpectrum has no color args")
    func spectrum() {
        let r = LEDExtendedCommands.effectSpectrum(zone: .matrix).finalized()
        #expect(r.argument(at: 2) == 0x03) // spectrum effect id
        #expect(r.dataSize == 0x06)
    }

    @Test("setBrightness (extended) puts value at args[2]")
    func brightness() {
        let r = LEDExtendedCommands.setBrightness(zone: .matrix, value: 200).finalized()
        #expect(r.commandClass == 0x0F)
        #expect(r.commandID.rawValue == 0x04)
        #expect(r.argument(at: 2) == 200)
    }
}

@Suite("Misc new commands")
struct MiscNewCommandsTests {
    @Test("getFirmwareVersion uses class 0x00, command 0x81")
    func firmware() {
        let r = MiscCommands.getFirmwareVersion().finalized()
        #expect(r.commandClass == 0x00)
        #expect(r.commandID.rawValue == 0x81)
    }

    @Test("parseFirmwareVersion formats major.minor")
    func firmwareParse() {
        var resp = RazerReport()
        resp.setArgument(0x03, at: 0)
        resp.setArgument(0x0A, at: 1)
        #expect(MiscCommands.parseFirmwareVersion(resp) == "v3.10")
    }

    @Test("setIdleTime clamps to [60, 900]s")
    func idleTime() {
        let low = MiscCommands.setIdleTime(seconds: 10)
        #expect((UInt16(low.argument(at: 0)) << 8) | UInt16(low.argument(at: 1)) == 60)
        let high = MiscCommands.setIdleTime(seconds: 3_000)
        #expect((UInt16(high.argument(at: 0)) << 8) | UInt16(high.argument(at: 1)) == 900)
    }

    @Test("setLowBatteryThreshold clamps to openrazer band [0x0C, 0x3F]")
    func lowBattery() {
        let low = MiscCommands.setLowBatteryThreshold(percent: 1)
        #expect(low.argument(at: 0) == 0x0C)
        let high = MiscCommands.setLowBatteryThreshold(percent: 50)
        #expect(high.argument(at: 0) == 0x3F)
    }

    @Test("setDPIStages writes count + active + 7 bytes per stage")
    func stagesLayout() {
        let r = MiscCommands.setDPIStages(
            [(800, 800), (1600, 1600), (3200, 3200)],
            activeStage: 2
        )
        #expect(r.dataSize == 0x26)
        #expect(r.argument(at: 1) == 2)   // active
        #expect(r.argument(at: 2) == 3)   // count
        // First stage (offset 3): stage=0, DPI=0x03,0x20,0x03,0x20
        #expect(r.argument(at: 3) == 0)
        #expect(r.argument(at: 4) == 0x03)
        #expect(r.argument(at: 5) == 0x20)
        #expect(r.argument(at: 6) == 0x03)
        #expect(r.argument(at: 7) == 0x20)
    }

    @Test("parseDPIStages round-trips through setDPIStages")
    func stagesRoundTrip() {
        let input: [(UInt16, UInt16)] = [(400, 400), (800, 800), (1600, 1600)]
        let req = MiscCommands.setDPIStages(input, activeStage: 1)
        // Treat the request's argument buffer as the "response" payload
        // (they share layout).
        var resp = RazerReport()
        for i in 0..<26 {
            resp.setArgument(req.argument(at: i), at: i)
        }
        let parsed = MiscCommands.parseDPIStages(resp)
        #expect(parsed.activeStage == 1)
        #expect(parsed.stages.count == 3)
        #expect(parsed.stages[0].x == 400)
        #expect(parsed.stages[1].x == 800)
        #expect(parsed.stages[2].x == 1600)
    }
}
