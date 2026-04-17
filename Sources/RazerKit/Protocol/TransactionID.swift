import Foundation

/// Packed 8-bit transaction identifier.
///
/// Mirrors `union transaction_id_union` in openrazer/driver/razercommon.h:102-108.
/// Layout: high 3 bits = device index, low 5 bits = transaction id.
public struct TransactionID: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(device: UInt8, id: UInt8) {
        let packed = ((device & 0b111) << 5) | (id & 0b11111)
        self.rawValue = packed
    }

    public var device: UInt8 { (rawValue >> 5) & 0b111 }
    public var id: UInt8 { rawValue & 0b11111 }

    public static let zero = TransactionID(rawValue: 0x00)
    public static let standard = TransactionID(rawValue: 0xFF)
}
