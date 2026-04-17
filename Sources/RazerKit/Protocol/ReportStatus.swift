import Foundation

public enum ReportStatus: UInt8, Sendable, Equatable {
    case new = 0x00
    case busy = 0x01
    case successful = 0x02
    case failure = 0x03
    case timeout = 0x04
    case notSupported = 0x05

    public var isOK: Bool { self == .successful }
}
