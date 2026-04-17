import Foundation

public struct RazerRGB: Sendable, Hashable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(rgb24: UInt32) {
        self.r = UInt8((rgb24 >> 16) & 0xFF)
        self.g = UInt8((rgb24 >> 8) & 0xFF)
        self.b = UInt8(rgb24 & 0xFF)
    }

    public static let black = RazerRGB(r: 0, g: 0, b: 0)
    public static let white = RazerRGB(r: 255, g: 255, b: 255)
    public static let razerGreen = RazerRGB(rgb24: 0x44D62C)
}

/// Per-zone LED identifier (from openrazer/driver/razercommon.h LED constants).
public enum LEDZone: UInt8, Sendable, Hashable, CaseIterable {
    case matrix = 0x00          // whole-device backlight (matrix)
    case scrollWheel = 0x01
    case battery = 0x03
    case logo = 0x04
    case backlight = 0x05
    case macro = 0x07
    case gameMode = 0x08
    case rightSide = 0x10
    case leftSide = 0x11
    case charging = 0x20
}

/// Effect speed — valid range varies per effect:
/// * Reactive: 1–4
/// * Starlight: 1–3
public enum EffectSpeed: UInt8, Sendable, Hashable, CaseIterable {
    case fastest = 0x01
    case fast = 0x02
    case medium = 0x03
    case slow = 0x04
}

/// Wave direction. Newer extended path uses 0x01/0x02; older standard path
/// uses the same encoding. Device families that accept 0x00/0x01 handle
/// clamping internally.
public enum WaveDirection: UInt8, Sendable, Hashable {
    case left = 0x01
    case right = 0x02
}
