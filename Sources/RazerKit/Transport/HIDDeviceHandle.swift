import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

/// Lightweight, sendable pointer to a matched Razer device. The actual
/// `IOHIDDevice` reference is owned internally by `HIDTransport`; this handle
/// is what callers use to address commands to a specific device.
public struct HIDDeviceHandle: Sendable, Hashable, Identifiable {
    public let id: UInt64
    public let vendorID: Int
    public let productID: Int
    public let name: String
    public let serialNumber: String?
    public let manufacturer: String?
    public let usagePage: Int
    public let usage: Int

    public init(
        id: UInt64,
        vendorID: Int,
        productID: Int,
        name: String,
        serialNumber: String?,
        manufacturer: String?,
        usagePage: Int,
        usage: Int
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.usagePage = usagePage
        self.usage = usage
    }
}
