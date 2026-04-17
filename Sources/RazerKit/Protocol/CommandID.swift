import Foundation

/// Packed 8-bit command identifier.
///
/// Mirrors `union command_id_union` in openrazer/driver/razercommon.h:110-116.
/// Bit 7 is direction (0 = Host→Device set, 1 = Device→Host get). Bits 6..0 = id.
public struct CommandID: RawRepresentable, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(direction: Direction, id: UInt8) {
        self.rawValue = (direction.rawValue << 7) | (id & 0b0111_1111)
    }

    public enum Direction: UInt8, Sendable {
        case set = 0x00
        case get = 0x01
    }

    public var direction: Direction {
        Direction(rawValue: (rawValue >> 7) & 0b1) ?? .set
    }

    public var id: UInt8 { rawValue & 0b0111_1111 }
}
