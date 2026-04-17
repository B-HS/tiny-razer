import Foundation
import ServiceManagement
import Observation

/// Thin wrapper around `SMAppService.mainApp` to toggle "Open at Login".
/// Registers / unregisters the running app bundle as a login item; the
/// registration survives reboots and is stored in the user's login database.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool

    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.ui.error("LaunchAtLogin toggle failed: \(String(describing: error))")
        }
        refresh()
    }

    /// Re-read the current status from the system.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// True when the system requires user approval in System Settings
    /// → Login Items before the registration takes effect.
    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
