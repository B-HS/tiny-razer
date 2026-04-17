import Foundation

/// Razer HID report checksum.
///
/// Ported from `razer_calculate_crc` in openrazer/driver/razercommon.c:131-144.
/// XOR of bytes [2, 88) in the 90-byte report.
public enum CRC {
    @inlinable
    public static func calculate(_ bytes: some Collection<UInt8>) -> UInt8 {
        precondition(bytes.count >= 88, "CRC input must be at least 88 bytes")
        var crc: UInt8 = 0
        var index = bytes.startIndex
        bytes.formIndex(&index, offsetBy: 2)
        let end = bytes.index(bytes.startIndex, offsetBy: 88)
        while index < end {
            crc ^= bytes[index]
            bytes.formIndex(after: &index)
        }
        return crc
    }
}
