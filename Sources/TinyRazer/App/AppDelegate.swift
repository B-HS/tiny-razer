import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let deviceManager = DeviceManager()
    let fieldPreferences = FieldPreferences()
    let launchAtLogin = LaunchAtLogin()
    private var statusBar: StatusBarController?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
            await self.deviceManager.start()
            self.statusBar = StatusBarController(
                manager: self.deviceManager,
                preferences: self.fieldPreferences
            )
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await self.deviceManager.stop()
        }
    }

    /// Tiny Razer is a menu-bar-only app — closing the settings window
    /// should just hide the window, not terminate the process.
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
