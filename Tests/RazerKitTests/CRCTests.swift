import Testing
@testable import RazerKit

@Suite("CRC (XOR of bytes 2..<88)")
struct CRCTests {
    @Test("empty report → CRC 0")
    func emptyCRC() {
        let bytes = [UInt8](repeating: 0, count: 90)
        #expect(CRC.calculate(bytes) == 0)
    }

    @Test("status/transaction/reserved bytes do not contribute")
    func excludesStatusAndReserved() {
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[0] = 0xFF // status
        bytes[1] = 0xFF // transaction_id
        bytes[88] = 0xFF // crc position itself excluded
        bytes[89] = 0xFF // reserved
        #expect(CRC.calculate(bytes) == 0)
    }

    @Test("single byte at position 6 flows through")
    func singleByteAtPosition6() {
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[6] = 0x04
        #expect(CRC.calculate(bytes) == 0x04)
    }

    @Test("matches hand-computed CRC for setDPI(800,800)")
    func setDPIExpectedCRC() {
        let report = MiscCommands.setDPI(x: 800, y: 800).finalized()
        // data_size(0x07) ^ class(0x04) ^ id(0x05) ^ VARSTORE(0x01)
        //   ^ 0x03 ^ 0x20 ^ 0x03 ^ 0x20 = 0x07
        #expect(report.crc == 0x07)
    }

    @Test("matches hand-computed CRC for getBatteryLevel")
    func batteryExpectedCRC() {
        let report = MiscCommands.getBatteryLevel().finalized()
        // size(0x02) ^ class(0x07) ^ id(0x80) = 0x85
        #expect(report.crc == 0x85)
    }

    @Test("matches hand-computed CRC for setPollingRate(1000Hz)")
    func pollingRateExpectedCRC() {
        let report = MiscCommands.setPollingRate(.hz1000).finalized()
        // size(0x01) ^ class(0x00) ^ id(0x05) ^ arg[0]=0x01 = 0x05
        #expect(report.crc == 0x05)
    }
}
