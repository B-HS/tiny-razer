import Testing
@testable import RazerKit

@Suite("Device catalog")
struct DeviceCatalogTests {
    @Test("DeathAdder V3 Pro wired (primary + ALT) are both present")
    func wiredResolution() {
        let primary = DeviceCatalog.descriptor(for: 0x00B6)
        let alt = DeviceCatalog.descriptor(for: 0x00C2)
        #expect(primary != nil)
        #expect(alt != nil)
        #expect(primary?.isWireless == false)
        #expect(alt?.isWireless == false)
        #expect(primary?.shortName.contains("DeathAdder V3 Pro") == true)
    }

    @Test("DeathAdder V3 Pro wireless has battery + charging")
    func wirelessBattery() {
        let desc = DeviceCatalog.descriptor(for: 0x00B7)
        #expect(desc?.capabilities.contains(.battery) == true)
        #expect(desc?.capabilities.contains(.charging) == true)
        #expect(desc?.isWireless == true)
    }

    @Test("Modern V3-era devices use transaction_id 0x1f")
    func modernTransactionID() {
        let desc = DeviceCatalog.descriptor(for: 0x00B7) // DA V3 Pro wireless
        #expect(desc?.transactionID.rawValue == 0x1f)
    }

    @Test("HyperPolling dongle supports up to 8 kHz")
    func hyperPollingDongle() {
        let desc = DeviceCatalog.descriptor(for: 0x00B3)
        #expect(desc != nil)
        #expect(desc?.capabilities.contains(.pollingRateHyper) == true)
        #expect(desc?.hyperPollingRates.contains(.hz8000) == true)
    }

    @Test("unknown PID returns nil")
    func unknownPID() {
        #expect(DeviceCatalog.descriptor(for: 0xDEAD) == nil)
    }

    @Test("catalog is non-empty and deduped")
    func catalogPopulated() {
        #expect(DeviceCatalog.all.count > 100)
        #expect(DeviceCatalog.supportedProductIDs.count > 100)
    }

    @Test("RazerDevice.from rejects non-Razer vendor")
    func wrongVendorRejected() {
        let nonRazer = HIDDeviceHandle(
            id: 1,
            vendorID: 0x046D,
            productID: 0x00B7,
            name: "Logitech impostor",
            serialNumber: nil,
            manufacturer: nil,
            usagePage: 0,
            usage: 0
        )
        #expect(RazerDevice.from(handle: nonRazer) == nil)
    }

    @Test("modelKey collapses wired/wireless/(Alt) variants of one model")
    func modelKeyCollapsesVariants() {
        let wired = DeviceCatalog.descriptor(for: 0x00B6)      // DeathAdder V3 Pro Wired
        let wiredAlt = DeviceCatalog.descriptor(for: 0x00C2)   // DeathAdder V3 Pro Wired (Alt)
        let wireless = DeviceCatalog.descriptor(for: 0x00B7)   // DeathAdder V3 Pro Wireless
        #expect(wired?.modelKey == wireless?.modelKey)
        #expect(wiredAlt?.modelKey == wireless?.modelKey)
        #expect(wired?.modelKey == "deathadder v3 pro")
    }

    @Test("modelKey keeps distinct models distinct")
    func modelKeyDistinguishesModels() {
        // Same family, different generation qualifiers must not collapse.
        let v3pro = DeviceCatalog.descriptor(for: 0x00B7)?.modelKey      // DeathAdder V3 Pro Wireless
        let v2pro = DeviceCatalog.descriptor(for: 0x007C)?.modelKey      // DeathAdder V2 Pro Wired
        #expect(v3pro == "deathadder v3 pro")
        #expect(v2pro == "deathadder v2 pro")
        #expect(v3pro != v2pro)
    }

    @Test("RazerDevice.from accepts a Razer PID that's in the catalog")
    func knownRazerAccepted() {
        let handle = HIDDeviceHandle(
            id: 42,
            vendorID: 0x1532,
            productID: 0x00B7,
            name: "Razer DeathAdder V3 Pro",
            serialNumber: nil,
            manufacturer: "Razer Inc.",
            usagePage: 1,
            usage: 2
        )
        let device = RazerDevice.from(handle: handle)
        #expect(device != nil)
        #expect(device?.supports(.battery) == true)
    }
}
