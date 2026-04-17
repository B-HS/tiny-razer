import Foundation

public enum TransportError: Error, Sendable, Equatable {
    case transportNotStarted
    case deviceNotConnected
    case invalidResponseLength(Int)
    case ioKitError(Int32)
    case reportStatus(ReportStatus)
    case timeout
    case notPermitted

    public var description: String {
        switch self {
        case .transportNotStarted: return "HIDTransport has not been started"
        case .deviceNotConnected: return "device is not connected"
        case let .invalidResponseLength(n): return "received response of unexpected length \(n)"
        case let .ioKitError(code):
            return String(format: "IOKit error 0x%08X", UInt32(bitPattern: code))
        case let .reportStatus(status): return "Razer device reported status \(status)"
        case .timeout: return "request timed out"
        case .notPermitted: return "Input Monitoring permission required"
        }
    }

    /// IOKit's kIOReturnNotPermitted — macOS TCC denying HID access.
    public static let kIOReturnNotPermitted: Int32 = Int32(bitPattern: 0xE00002E2)

    public var isPermissionDenied: Bool {
        switch self {
        case .notPermitted: return true
        case let .ioKitError(code): return code == Self.kIOReturnNotPermitted
        default: return false
        }
    }
}
