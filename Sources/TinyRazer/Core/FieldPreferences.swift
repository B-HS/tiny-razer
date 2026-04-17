import Foundation
import Observation
import RazerKit

/// User-selectable state rows a device can display.
enum FieldKind: String, CaseIterable, Sendable, Hashable, Identifiable {
    case dpi
    case pollingRate
    case battery
    case charging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dpi: return "DPI"
        case .pollingRate: return "Polling rate"
        case .battery: return "Battery"
        case .charging: return "Charging"
        }
    }

    var systemImage: String {
        switch self {
        case .dpi: return "scope"
        case .pollingRate: return "waveform.path.ecg"
        case .battery: return "battery.75"
        case .charging: return "bolt.fill"
        }
    }

    var requiredCapability: Capability {
        switch self {
        case .dpi: return .dpi
        case .pollingRate: return .pollingRate
        case .battery: return .battery
        case .charging: return .charging
        }
    }
}

/// Persists per-device "which rows to display" preferences in UserDefaults.
/// Keyed by productID so each physical device model remembers independently.
@MainActor
@Observable
final class FieldPreferences {
    private let defaults: UserDefaults
    private let prefix = "fieldPrefs.v1."

    /// Observable tick used to force SwiftUI to re-read visibility when we
    /// mutate UserDefaults (UserDefaults isn't natively observable).
    private(set) var revision: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func visibleFields(for descriptor: DeviceDescriptor) -> Set<FieldKind> {
        let key = key(for: descriptor)
        if let raw = defaults.array(forKey: key) as? [String] {
            return Set(raw.compactMap(FieldKind.init(rawValue:)))
        }
        return defaultFields(for: descriptor)
    }

    func isVisible(_ field: FieldKind, for descriptor: DeviceDescriptor) -> Bool {
        visibleFields(for: descriptor).contains(field)
    }

    func toggle(_ field: FieldKind, for descriptor: DeviceDescriptor) {
        var current = visibleFields(for: descriptor)
        if current.contains(field) {
            current.remove(field)
        } else {
            current.insert(field)
        }
        defaults.set(current.map(\.rawValue).sorted(), forKey: key(for: descriptor))
        revision &+= 1
    }

    func availableFields(for descriptor: DeviceDescriptor) -> [FieldKind] {
        FieldKind.allCases.filter { descriptor.capabilities.contains($0.requiredCapability) }
    }

    private func defaultFields(for descriptor: DeviceDescriptor) -> Set<FieldKind> {
        Set(availableFields(for: descriptor))
    }

    private func key(for descriptor: DeviceDescriptor) -> String {
        let pidKey = descriptor.productIDs.sorted().map { String(format: "%04x", $0) }.joined(separator: "-")
        return "\(prefix)\(pidKey)"
    }
}
