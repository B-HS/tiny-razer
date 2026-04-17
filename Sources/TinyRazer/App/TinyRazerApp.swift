import SwiftUI
import RazerKit

@main
struct TinyRazerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                manager: appDelegate.deviceManager,
                preferences: appDelegate.fieldPreferences
            )
        } label: {
            MenuBarLabel(
                manager: appDelegate.deviceManager,
                preferences: appDelegate.fieldPreferences
            )
        }
        .menuBarExtraStyle(.window)

        Window("Tiny Razer", id: "tinyRazerSettings") {
            SettingsScene(
                manager: appDelegate.deviceManager,
                preferences: appDelegate.fieldPreferences,
                launchAtLogin: appDelegate.launchAtLogin
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 520)
    }
}

/// Status-item label shown in the macOS menu bar. Mirrors apps like Stats /
/// iStat Menus: icon plus whichever metrics the user toggled on for this
/// device (battery, DPI, polling rate, charging indicator).
///
/// Implementation note: MenuBarExtra labels are drawn inside an NSStatusItem
/// which historically ignores/drops complex SwiftUI view hierarchies. A
/// single `Text` composed via string concatenation + inline SF Symbol
/// interpolation renders reliably.
private struct MenuBarLabel: View {
    @Bindable var manager: DeviceManager
    @Bindable var preferences: FieldPreferences

    var body: some View {
        // MenuBarExtra's label only renders HStack children reliably when
        // each child is a single View. Image + one concatenated Text works;
        // HStack + ForEach does not.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: iconName)
            if !metricString.isEmpty {
                Text(metricString)
                    .monospacedDigit()
            }
        }
    }

    private var primary: DeviceState? { manager.devices.first }

    private var iconName: String {
        guard let p = primary else { return "computermouse" }
        return IconForCategory.symbol(for: p.device.category, filled: true)
    }

    private var metricString: String {
        _ = preferences.revision
        guard let state = primary else { return "" }
        let descriptor = state.device.descriptor
        var parts: [String] = []
        for field in preferences.availableFields(for: descriptor)
            where preferences.isVisible(field, for: descriptor) {
            let rendered = render(field: field, state: state)
            if !rendered.isEmpty { parts.append(rendered) }
        }
        return parts.joined(separator: "  ")
    }

    private func render(field: FieldKind, state: DeviceState) -> String {
        switch field {
        case .dpi:
            guard let x = state.dpiX else { return "—" }
            return x >= 1000 ? String(format: "%.1fk", Double(x) / 1000) : "\(x)"
        case .pollingRate:
            guard let rate = state.pollingRate else { return "—Hz" }
            return rate.rawValue >= 1000
                ? "\(rate.rawValue / 1000)kHz"
                : "\(rate.rawValue)Hz"
        case .battery:
            guard let p = state.batteryPercent else { return "—%" }
            return "\(p)%"
        case .charging:
            // Show the charging indicator only while actually charging. When
            // the device is on battery the percent readout already conveys
            // that — a second icon there just adds noise.
            guard state.isCharging == true else { return "" }
            return "⚡"
        }
    }
}

/// Central category → SF Symbol mapping used by every device icon in the app.
enum IconForCategory {
    static func symbol(for category: DeviceCategory, filled: Bool = false) -> String {
        switch category {
        case .mouse: return filled ? "computermouse.fill" : "computermouse"
        case .keyboard: return "keyboard"
        case .headset: return "headphones"
        case .mousepad: return "rectangle.fill.on.rectangle.fill"
        case .dock: return "cable.connector"
        case .eGPU: return "cpu"
        case .accessory: return "dot.radiowaves.left.and.right"
        }
    }

    static func accentColor(for category: DeviceCategory) -> Color {
        switch category {
        case .mouse: return .green
        case .keyboard: return .purple
        case .headset: return .orange
        case .mousepad: return .cyan
        case .dock: return .blue
        case .eGPU: return .pink
        case .accessory: return .indigo
        }
    }
}
