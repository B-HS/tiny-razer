import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let deviceManager = DeviceManager()
    let fieldPreferences = FieldPreferences()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
            await self.deviceManager.start()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await self.deviceManager.stop()
        }
    }
}
