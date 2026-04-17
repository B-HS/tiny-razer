import Testing
@testable import RazerKit

/// Byte-for-byte verification against openrazer C source.
///
/// Each vector is hand-computed from the builder in razerchromacommon.c and the
/// razer_report layout (razercommon.h:135). These are the canonical regression
/// tests — if these ever drift from the C output, the wire protocol is broken.
@Suite("Command byte vectors")
struct CommandByteVectorTests {
    @Test("setDPI(800, 800) produces exact wire bytes")
    func setDPI800() {
        let report = MiscCommands.setDPI(x: 800, y: 800).finalized()
        let bytes = report.toBytes()

        #expect(bytes[0] == 0x00) // status
        #expect(bytes[1] == 0x00) // transaction_id
        #expect(bytes[2] == 0x00) // remaining_packets hi
        #expect(bytes[3] == 0x00) // remaining_packets lo
        #expect(bytes[4] == 0x00) // protocol_type
        #expect(bytes[5] == 0x07) // data_size
        #expect(bytes[6] == 0x04) // command_class
        #expect(bytes[7] == 0x05) // command_id (direction=set, id=0x05)
        #expect(bytes[8] == 0x01) // VARSTORE
        #expect(bytes[9] == 0x03) // dpi_x hi (800 = 0x0320)
        #expect(bytes[10] == 0x20) // dpi_x lo
        #expect(bytes[11] == 0x03) // dpi_y hi
        #expect(bytes[12] == 0x20) // dpi_y lo
        #expect(bytes[13] == 0x00) // padding
        #expect(bytes[14] == 0x00) // padding
        #expect(bytes[88] == 0x07) // crc
        #expect(bytes[89] == 0x00) // reserved
    }

    @Test("setDPI clamps to [100, 45000]")
    func setDPIClamping() {
        let low = MiscCommands.setDPI(x: 10, y: 10)
        #expect(low.argument(at: 1) == 0x00)
        #expect(low.argument(at: 2) == 100) // clamped to 100

        let high = MiscCommands.setDPI(x: 60_000, y: 60_000)
        #expect((UInt16(high.argument(at: 1)) << 8) | UInt16(high.argument(at: 2)) == 45_000)
    }

    @Test("getDPI is a GET with 7-byte data size")
    func getDPIVector() {
        let report = MiscCommands.getDPI().finalized()
        let bytes = report.toBytes()

        #expect(bytes[5] == 0x07)
        #expect(bytes[6] == 0x04)
        #expect(bytes[7] == 0x85) // direction=get | id=0x05
        #expect(bytes[8] == 0x01) // VARSTORE
    }

    @Test("setPollingRate encodes classic codes")
    func pollingRateClassicCodes() {
        #expect(MiscCommands.setPollingRate(.hz1000).argument(at: 0) == 0x01)
        #expect(MiscCommands.setPollingRate(.hz500).argument(at: 0) == 0x02)
        #expect(MiscCommands.setPollingRate(.hz125).argument(at: 0) == 0x08)
    }

    @Test("setPollingRate2 encodes hyper codes")
    func pollingRateHyperCodes() {
        #expect(MiscCommands.setPollingRate2(.hz8000).argument(at: 1) == 0x01)
        #expect(MiscCommands.setPollingRate2(.hz4000).argument(at: 1) == 0x02)
        #expect(MiscCommands.setPollingRate2(.hz2000).argument(at: 1) == 0x04)
        #expect(MiscCommands.setPollingRate2(.hz1000).argument(at: 1) == 0x08)
        #expect(MiscCommands.setPollingRate2(.hz500).argument(at: 1) == 0x10)
        #expect(MiscCommands.setPollingRate2(.hz125).argument(at: 1) == 0x40)
    }

    @Test("getBatteryLevel uses class 0x07, command 0x80")
    func batteryVector() {
        let report = MiscCommands.getBatteryLevel().finalized()
        let bytes = report.toBytes()
        #expect(bytes[5] == 0x02)
        #expect(bytes[6] == 0x07)
        #expect(bytes[7] == 0x80)
    }

    @Test("getChargingStatus uses class 0x07, command 0x84")
    func chargingVector() {
        let report = MiscCommands.getChargingStatus().finalized()
        let bytes = report.toBytes()
        #expect(bytes[5] == 0x02)
        #expect(bytes[6] == 0x07)
        #expect(bytes[7] == 0x84)
    }

    @Test("parseDPI round-trip")
    func parseDPIRoundTrip() {
        let request = MiscCommands.setDPI(x: 1600, y: 3200)
        var response = RazerReport()
        response.setArgument(0x01, at: 0)
        response.setArgument(request.argument(at: 1), at: 1)
        response.setArgument(request.argument(at: 2), at: 2)
        response.setArgument(request.argument(at: 3), at: 3)
        response.setArgument(request.argument(at: 4), at: 4)

        let (x, y) = MiscCommands.parseDPI(response)
        #expect(x == 1600)
        #expect(y == 3200)
    }

    @Test("parsePollingRate decodes classic codes")
    func parsePollingRateClassic() {
        var r = RazerReport()
        r.setArgument(0x01, at: 0); #expect(MiscCommands.parsePollingRate(r) == .hz1000)
        r.setArgument(0x02, at: 0); #expect(MiscCommands.parsePollingRate(r) == .hz500)
        r.setArgument(0x08, at: 0); #expect(MiscCommands.parsePollingRate(r) == .hz125)
        r.setArgument(0xFF, at: 0); #expect(MiscCommands.parsePollingRate(r) == nil)
    }

    @Test("parsePollingRate2 decodes hyper codes (arg[1])")
    func parsePollingRate2Hyper() {
        var r = RazerReport()
        r.setArgument(0x01, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz8000)
        r.setArgument(0x02, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz4000)
        r.setArgument(0x04, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz2000)
        r.setArgument(0x08, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz1000)
        r.setArgument(0x10, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz500)
        r.setArgument(0x40, at: 1); #expect(MiscCommands.parsePollingRate2(r) == .hz125)
        r.setArgument(0x00, at: 1); #expect(MiscCommands.parsePollingRate2(r) == nil)
    }

    @Test("parseBatteryLevel scales 0..255 to 0..100%")
    func parseBatteryLevel() {
        var r = RazerReport()
        r.setArgument(0x00, at: 1); #expect(MiscCommands.parseBatteryLevel(r) == 0)
        r.setArgument(0xFF, at: 1); #expect(MiscCommands.parseBatteryLevel(r) == 100)
        r.setArgument(0x80, at: 1); #expect(MiscCommands.parseBatteryLevel(r) == 50)
    }

    @Test("parseChargingStatus reads arg[1] as bool")
    func parseChargingStatus() {
        var r = RazerReport()
        r.setArgument(0x00, at: 1); #expect(MiscCommands.parseChargingStatus(r) == false)
        r.setArgument(0x01, at: 1); #expect(MiscCommands.parseChargingStatus(r) == true)
        r.setArgument(0xFF, at: 1); #expect(MiscCommands.parseChargingStatus(r) == true)
    }
}
