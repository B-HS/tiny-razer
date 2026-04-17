import Foundation

/// 90-byte HID feature report exchanged with Razer peripherals.
///
/// Binary layout (from openrazer/driver/razercommon.h:135-146):
/// ```
/// byte 0      status
/// byte 1      transaction_id (device[3] | id[5])
/// bytes 2..3  remaining_packets (big endian u16)
/// byte 4      protocol_type (always 0x00)
/// byte 5      data_size (≤ 80)
/// byte 6      command_class
/// byte 7      command_id (direction[1] | id[7])
/// bytes 8..87 arguments (80 bytes)
/// byte 88     crc (XOR of bytes 2..<88)
/// byte 89     reserved (0x00)
/// ```
public struct RazerReport: Sendable, Equatable {
    public static let byteCount = 90
    public static let argumentsOffset = 8
    public static let argumentsCount = 80
    public static let crcOffset = 88

    private var storage: [UInt8]

    public init() {
        self.storage = Array(repeating: 0, count: Self.byteCount)
    }

    public init(
        transactionID: TransactionID = .zero,
        commandClass: UInt8,
        commandID: CommandID,
        dataSize: UInt8,
        arguments: [UInt8] = []
    ) {
        precondition(dataSize <= UInt8(Self.argumentsCount), "data_size must be ≤ 80")
        precondition(arguments.count <= Self.argumentsCount, "arguments must fit in 80 bytes")

        self.storage = Array(repeating: 0, count: Self.byteCount)
        self.transactionID = transactionID
        self.commandClass = commandClass
        self.commandID = commandID
        self.dataSize = dataSize
        if !arguments.isEmpty {
            setArguments(arguments)
        }
    }

    // MARK: - Typed accessors

    public var status: ReportStatus {
        get { ReportStatus(rawValue: storage[0]) ?? .new }
        set { storage[0] = newValue.rawValue }
    }

    public var transactionID: TransactionID {
        get { TransactionID(rawValue: storage[1]) }
        set { storage[1] = newValue.rawValue }
    }

    public var remainingPackets: UInt16 {
        get { (UInt16(storage[2]) << 8) | UInt16(storage[3]) }
        set {
            storage[2] = UInt8(truncatingIfNeeded: newValue >> 8)
            storage[3] = UInt8(truncatingIfNeeded: newValue)
        }
    }

    public var protocolType: UInt8 {
        get { storage[4] }
        set { storage[4] = newValue }
    }

    public var dataSize: UInt8 {
        get { storage[5] }
        set {
            precondition(newValue <= UInt8(Self.argumentsCount), "data_size must be ≤ 80")
            storage[5] = newValue
        }
    }

    public var commandClass: UInt8 {
        get { storage[6] }
        set { storage[6] = newValue }
    }

    public var commandID: CommandID {
        get { CommandID(rawValue: storage[7]) }
        set { storage[7] = newValue.rawValue }
    }

    public var crc: UInt8 {
        get { storage[Self.crcOffset] }
        set { storage[Self.crcOffset] = newValue }
    }

    public var reserved: UInt8 {
        get { storage[89] }
        set { storage[89] = newValue }
    }

    // MARK: - Arguments access

    public func argument(at index: Int) -> UInt8 {
        precondition(index >= 0 && index < Self.argumentsCount, "argument index out of range")
        return storage[Self.argumentsOffset + index]
    }

    public mutating func setArgument(_ value: UInt8, at index: Int) {
        precondition(index >= 0 && index < Self.argumentsCount, "argument index out of range")
        storage[Self.argumentsOffset + index] = value
    }

    public mutating func setArguments(_ values: [UInt8], startingAt offset: Int = 0) {
        precondition(offset + values.count <= Self.argumentsCount, "arguments overflow")
        for (i, value) in values.enumerated() {
            storage[Self.argumentsOffset + offset + i] = value
        }
    }

    public func argumentsSlice(count: Int, startingAt offset: Int = 0) -> [UInt8] {
        precondition(offset + count <= Self.argumentsCount, "arguments slice out of range")
        return Array(storage[(Self.argumentsOffset + offset)..<(Self.argumentsOffset + offset + count)])
    }

    // MARK: - CRC

    public mutating func finalize(transactionID override: TransactionID? = nil) {
        if let override {
            self.transactionID = override
        }
        self.crc = CRC.calculate(storage)
    }

    public func finalized(transactionID override: TransactionID? = nil) -> RazerReport {
        var copy = self
        copy.finalize(transactionID: override)
        return copy
    }

    public func isCRCValid() -> Bool {
        CRC.calculate(storage) == crc
    }

    // MARK: - Serialization

    public func toData() -> Data {
        Data(storage)
    }

    public func toBytes() -> [UInt8] {
        storage
    }

    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.storage = Array(data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        self.storage = bytes
    }
}
