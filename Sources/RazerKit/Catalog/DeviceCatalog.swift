import Foundation

/// Static registry of every Razer device Tiny Razer knows how to talk to.
///
/// The entire catalog is **generated** from openrazer upstream (see
/// `scripts/gen-catalog.ts`). No per-device values are hand-authored —
/// transaction IDs, wireless flag, hyper-polling support, capabilities, and
/// max DPI are all extracted from openrazer's C driver switch-cases and
/// Python daemon hardware classes. Regenerate with
/// `bun run scripts/gen-catalog.ts`.
public enum DeviceCatalog {
    public static let all: [DeviceDescriptor] =
        GeneratedMouseCatalog.descriptors
        + GeneratedKeyboardCatalog.descriptors
        + GeneratedHeadsetCatalog.descriptors
        + GeneratedMousepadCatalog.descriptors
        + GeneratedAccessoryCatalog.descriptors

    private static let byProductID: [Int: DeviceDescriptor] = {
        var map: [Int: DeviceDescriptor] = [:]
        for descriptor in all {
            for pid in descriptor.productIDs where map[pid] == nil {
                map[pid] = descriptor
            }
        }
        return map
    }()

    public static func descriptor(for productID: Int) -> DeviceDescriptor? {
        byProductID[productID]
    }

    public static var supportedProductIDs: Set<Int> {
        Set(byProductID.keys)
    }
}
