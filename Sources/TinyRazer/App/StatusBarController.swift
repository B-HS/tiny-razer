import AppKit
import SwiftUI
import Observation

/// Owns an `NSStatusItem` and renders its label directly via AppKit —
/// SwiftUI `MenuBarExtra` labels can't keep an icon and its metric text
/// on the same baseline, so we drop to an `NSAttributedString` with the
/// SF Symbol embedded as a text attachment (the same approach Apple's
/// battery / Wi-Fi indicators use).
///
/// The popover content is a SwiftUI view hosted by `NSHostingController`,
/// so `MenuBarView` is reused unchanged.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let manager: DeviceManager
    private let preferences: FieldPreferences
    private var observerTask: Task<Void, Never>?

    init(manager: DeviceManager, preferences: FieldPreferences) {
        self.manager = manager
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = false

        super.init()

        if let button = statusItem.button {
            button.action = #selector(buttonClicked(_:))
            button.target = self
            button.imagePosition = .imageLeading
        }

        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(manager: manager, preferences: preferences)
        )

        // Observe state changes and redraw the title. Using a polling loop
        // every 200 ms is the simplest way to pick up `@Observable` mutations
        // (metric values, connect/disconnect, preference toggles) without
        // plumbing a Combine publisher through every source of truth.
        observerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateLabel()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        updateLabel()
    }

    deinit {
        observerTask?.cancel()
    }

    // MARK: - Rendering

    private func updateLabel() {
        guard let button = statusItem.button else { return }

        let iconName = primaryIconName
        let text = metricString

        let attributed = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)

        // Icon as a text attachment, offset vertically so its visual centre
        // sits on the same line as the digits.
        if let image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        ) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let h = image.size.height
            let w = image.size.width
            attachment.bounds = NSRect(x: 0, y: -3, width: w, height: h)
            attributed.append(NSAttributedString(attachment: attachment))
        }

        if !text.isEmpty {
            attributed.append(NSAttributedString(
                string: "  " + text,
                attributes: [
                    .font: font,
                    .baselineOffset: 0,
                ]
            ))
        }

        button.attributedTitle = attributed
    }

    // MARK: - Label data

    private var primary: DeviceState? { manager.devices.first }

    private var primaryIconName: String {
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
            guard state.isCharging == true else { return "" }
            return "⚡"
        }
    }

    // MARK: - Popover

    @objc private func buttonClicked(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
