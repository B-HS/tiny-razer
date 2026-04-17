import Testing
@testable import RazerKit

@Suite("RazerKit basics")
struct RazerKitBasicsTests {
    @Test("vendor ID is Razer")
    func vendorID() {
        #expect(RazerKit.vendorID == 0x1532)
    }

    @Test("HID report length is 90 bytes")
    func reportLength() {
        #expect(RazerKit.reportLength == 90)
    }

    @Test("HID feature report wValue is 0x300")
    func reportWValue() {
        #expect(RazerKit.reportWValue == 0x0300)
    }
}
