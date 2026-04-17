import SwiftUI
import RazerKit

@main
struct TinyRazerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
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
