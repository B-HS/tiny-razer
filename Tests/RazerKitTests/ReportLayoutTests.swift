import Testing
@testable import RazerKit

@Suite("RazerReport layout")
struct ReportLayoutTests {
    @Test("serialises to exactly 90 bytes")
    func serialisedLength() {
        let report = RazerReport(
            commandClass: 0x04,
            commandID: CommandID(direction: .set, id: 0x05),
            dataSize: 0x07
        )
        #expect(report.toBytes().count == 90)
        #expect(report.toData().count == 90)
    }

    @Test("field offsets match openrazer binary layout")
    func fieldOffsets() {
        var report = RazerReport()
        report.status = .successful
        report.transactionID = TransactionID(rawValue: 0x1F)
        report.remainingPackets = 0x0102
        report.protocolType = 0xAA
        report.dataSize = 0x07
        report.commandClass = 0x04
        report.commandID = CommandID(rawValue: 0x85)
        report.setArgument(0xDE, at: 0)
        report.setArgument(0xAD, at: 79)
        report.crc = 0x42
        report.reserved = 0x33

        let bytes = report.toBytes()
        #expect(bytes[0] == 0x02) // status = successful
        #expect(bytes[1] == 0x1F) // transaction_id
        #expect(bytes[2] == 0x01) // remaining hi (big endian)
        #expect(bytes[3] == 0x02) // remaining lo
        #expect(bytes[4] == 0xAA) // protocol_type
        #expect(bytes[5] == 0x07) // data_size
        #expect(bytes[6] == 0x04) // command_class
        #expect(bytes[7] == 0x85) // command_id
        #expect(bytes[8] == 0xDE) // arg[0]
        #expect(bytes[87] == 0xAD) // arg[79]
        #expect(bytes[88] == 0x42) // crc
        #expect(bytes[89] == 0x33) // reserved
    }

    @Test("round-trips through Data")
    func roundTrip() {
        var original = RazerReport(
            commandClass: 0x04,
            commandID: CommandID(direction: .set, id: 0x05),
            dataSize: 0x07,
            arguments: [0x01, 0x03, 0x20, 0x03, 0x20]
        )
        original.finalize()

        let data = original.toData()
        let decoded = RazerReport(data: data)
        #expect(decoded == original)
    }

    @Test("rejects wrong-sized input")
    func rejectsWrongSize() {
        #expect(RazerReport(bytes: [0x00]) == nil)
        #expect(RazerReport(bytes: Array(repeating: 0, count: 89)) == nil)
        #expect(RazerReport(bytes: Array(repeating: 0, count: 91)) == nil)
    }

    @Test("TransactionID packs device and id bits")
    func transactionIDPacking() {
        let tid = TransactionID(device: 0b101, id: 0b01010)
        #expect(tid.rawValue == 0b101_01010)
        #expect(tid.device == 0b101)
        #expect(tid.id == 0b01010)
    }

    @Test("CommandID direction bit")
    func commandIDDirection() {
        let setCmd = CommandID(direction: .set, id: 0x05)
        #expect(setCmd.rawValue == 0x05)
        #expect(setCmd.direction == .set)

        let getCmd = CommandID(direction: .get, id: 0x05)
        #expect(getCmd.rawValue == 0x85)
        #expect(getCmd.direction == .get)
        #expect(getCmd.id == 0x05)
    }
}
