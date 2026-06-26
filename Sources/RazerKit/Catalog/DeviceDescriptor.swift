import Foundation

/// Static description of a supported Razer device. One descriptor usually
/// covers multiple USB product IDs (wired + wireless + "ALT" variants).
public struct DeviceDescriptor: Sendable, Hashable {
    public let displayName: String
    public let shortName: String
    public let category: DeviceCategory
    public let productIDs: Set<Int>
    public let capabilities: Set<Capability>
    /// Maximum supported DPI if applicable, else 0.
    public let maxDPI: Int
    /// Polling rates usable via `setPollingRate2` (hyper). Empty means classic only.
    public let hyperPollingRates: Set<PollingRate>
    /// True if the device reports battery over the wireless transport.
    public let isWireless: Bool
    /// Per-device transaction_id byte required for the Razer control protocol.
    /// Newer devices (DeathAdder V3 Pro, Basilisk V3 Pro, etc.) demand 0x1f;
    /// older ones use 0x3f or 0xFF. Defaults to 0x1f which matches most modern hardware.
    /// Source: openrazer/driver/razermouse_driver.c switches per PID.
    public let transactionID: TransactionID

    public init(
        displayName: String,
        shortName: String,
        category: DeviceCategory,
        productIDs: Set<Int>,
        capabilities: Set<Capability>,
        maxDPI: Int = 0,
        hyperPollingRates: Set<PollingRate> = [],
        isWireless: Bool = false,
        transactionID: TransactionID = TransactionID(rawValue: 0x1f)
    ) {
        self.displayName = displayName
        self.shortName = shortName
        self.category = category
        self.productIDs = productIDs
        self.capabilities = capabilities
        self.maxDPI = maxDPI
        self.hyperPollingRates = hyperPollingRates
        self.isWireless = isWireless
        self.transactionID = transactionID
    }

    public func matches(productID: Int) -> Bool {
        productIDs.contains(productID)
    }

    /// Normalized model identity used to recognise the same physical device that
    /// enumerates under several product IDs — e.g. a wireless mouse seen over both
    /// its dongle and a USB cable. Trailing connectivity tokens ("Wired",
    /// "Wireless", "Receiver", "Dongle", "(Alt)") are dropped so the wired and
    /// wireless variants of one model collapse to the same key. Word-boundary
    /// based so it never truncates a real model name.
    public var modelKey: String {
        let connectivityTokens: Set<String> = ["wired", "wireless", "receiver", "dongle", "(alt)"]
        var tokens = shortName.split(separator: " ").map(String.init)
        while let last = tokens.last, connectivityTokens.contains(last.lowercased()) {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ").lowercased()
    }
}
