import SwiftUI
import RazerKit

struct MenuBarView: View {
    @Bindable var manager: DeviceManager
    @Bindable var preferences: FieldPreferences
    @Environment(\.openWindow) private var openWindow

    /// User's explicit device pick. `nil` means "use default" — which auto-
    /// resolves to the single connected device, or the list screen when
    /// multiple are attached. Keeping this as an *override* rather than the
    /// source of truth avoids a common MenuBarExtra issue where a stale ID
    /// survives device swaps that happen while the popup is closed.
    @State private var userSelectedDeviceID: UInt64?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xs)

            Divider()

            content

            Divider()

            footer
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 4)
        }
        .frame(width: 300)
        .onChange(of: manager.devices.map(\.id)) { _, _ in
            // Drop a user pick that no longer exists.
            if let sel = userSelectedDeviceID,
               !manager.devices.contains(where: { $0.id == sel }) {
                userSelectedDeviceID = nil
            }
        }
    }

    /// Derived: the device currently being shown in the detail pane.
    /// Recomputes on every body render, so it can never be "stuck" on a
    /// stale ID the way @State can when the popup was closed during a swap.
    private var activeDeviceState: DeviceState? {
        if let id = userSelectedDeviceID,
           let state = manager.devices.first(where: { $0.id == id }) {
            return state
        }
        if manager.devices.count == 1 {
            return manager.devices.first
        }
        return nil
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Back chevron only makes sense when there's more than one device
            // to go back to, and only when we're in detail (user pick or
            // single-device auto-resolve).
            if activeDeviceState != nil, manager.devices.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        userSelectedDeviceID = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
            }

            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Text(statusLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if !manager.devices.isEmpty {
                Button { refreshCurrent() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
        }
    }

    private var headerTitle: String {
        if let state = activeDeviceState {
            return state.shortName
        }
        return "Tiny Razer"
    }

    private var statusLine: String {
        if manager.needsInputMonitoringPermission { return "Permission" }
        if !manager.isRunning { return "Starting…" }
        let count = manager.devices.count
        return count == 0 ? "0 devices" : "\(count) connected"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if manager.needsInputMonitoringPermission {
            PermissionCard(manager: manager)
                .padding(DS.Spacing.sm)
        } else if manager.devices.isEmpty {
            emptyState
                .padding(DS.Spacing.md)
        } else if let state = activeDeviceState {
            ScrollView {
                DeviceDetailPane(state: state, manager: manager, preferences: preferences)
                    .padding(DS.Spacing.sm)
            }
            .frame(maxHeight: 420)
            .id(state.id)  // fresh hierarchy on device swap (wired ↔ wireless)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(manager.devices) { state in
                        DeviceListRow(state: state)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    userSelectedDeviceID = state.id
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "computermouse")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Razer devices")
                .font(.system(size: 12, weight: .medium))
            Text("Plug in a device or dongle.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            MenuButton(title: "Settings", systemImage: "slider.horizontal.3") {
                openWindow(id: "tinyRazerSettings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            MenuButton(title: "Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func refreshCurrent() {
        Task {
            if let state = activeDeviceState {
                await manager.readStateNow(for: state.id)
            } else {
                for device in manager.devices {
                    await manager.readStateNow(for: device.id)
                }
            }
        }
    }
}

// MARK: - List row

private struct DeviceListRow: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(IconForCategory.accentColor(for: state.device.category).opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: IconForCategory.symbol(for: state.device.category, filled: true))
                    .font(.system(size: 15))
                    .foregroundStyle(IconForCategory.accentColor(for: state.device.category))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(state.shortName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.device.descriptor.isWireless ? Color.blue : Color.green)
                        .frame(width: 5, height: 5)
                    Text(state.device.descriptor.isWireless ? "Wireless" : "Wired")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let percent = state.batteryPercent {
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(percent)%")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            // rely on default macOS pointer; highlight handled by pressing
            _ = hovering
        }
    }
}

// MARK: - Detail pane (menu bar)

private struct DeviceDetailPane: View {
    let state: DeviceState
    let manager: DeviceManager
    let preferences: FieldPreferences

    private static let dpiPresets: [UInt16] = [400, 800, 1600, 3200]

    @State private var showingFieldPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            hero

            if visible(.dpi) {
                dpiBlock
            }
            if visible(.pollingRate) {
                pollingBlock
            }
            if visible(.battery) {
                batteryBlock
            }
            if visible(.charging) {
                chargingBlock
            }

            customiseButton

            if let err = state.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var hero: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(IconForCategory.accentColor(for: state.device.category).opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: IconForCategory.symbol(for: state.device.category, filled: true))
                    .font(.system(size: 18))
                    .foregroundStyle(IconForCategory.accentColor(for: state.device.category))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.shortName)
                    .font(.system(size: 13, weight: .semibold))
                Text(state.device.descriptor.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var dpiBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(title: "DPI", systemImage: "scope")
                    Spacer()
                    Text(dpiDisplay)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.dpiX == nil ? .secondary : .primary)
                }
                PresetChips(
                    values: Self.dpiPresets,
                    selected: state.dpiX,
                    label: { "\($0)" },
                    onSelect: { value in
                        Task { await manager.setDPI(x: value, y: value, for: state.id) }
                    }
                )
                QuickCustomDPI(
                    initial: state.dpiX,
                    maxDPI: state.device.descriptor.maxDPI,
                    onApply: { value in
                        Task { await manager.setDPI(x: value, y: value, for: state.id) }
                    }
                )
            }
        }
    }

    private var pollingBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Polling rate", systemImage: "waveform.path.ecg")
                PresetChips(
                    values: pollingOptions,
                    selected: nil,
                    label: formatRate(_:),
                    onSelect: { rate in
                        Task { await manager.setPollingRate(rate, for: state.id) }
                    }
                )
            }
        }
    }

    private var batteryBlock: some View {
        Card {
            HStack(spacing: DS.Spacing.md) {
                BatteryRing(
                    percent: state.batteryPercent ?? 0,
                    isCharging: state.isCharging ?? false,
                    size: 40,
                    placeholder: state.batteryPercent == nil
                )
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(title: "Battery", systemImage: "battery.75")
                    HStack(spacing: 6) {
                        Text(batteryPercentText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        if state.isCharging == true {
                            ChargingPill(compact: true)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var chargingBlock: some View {
        Card {
            HStack {
                SectionLabel(title: "Charging", systemImage: "bolt.fill")
                Spacer()
                chargingStatusView
            }
        }
    }

    @ViewBuilder
    private var chargingStatusView: some View {
        switch state.isCharging {
        case .some(true):
            ChargingPill(compact: false)
        case .some(false):
            Text("On battery")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        case .none:
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var customiseButton: some View {
        // NSMenu (the SwiftUI Menu backing) caches Toggle checkmark state
        // across opens and doesn't always refresh when @Observable `revision`
        // ticks. Rebuild the whole Menu view on every revision change so the
        // menu items pick up the current visibility state.
        Menu {
            ForEach(preferences.availableFields(for: state.device.descriptor)) { field in
                let isOn = preferences.isVisible(field, for: state.device.descriptor)
                Button {
                    preferences.toggle(field, for: state.device.descriptor)
                } label: {
                    Label(
                        "\(isOn ? "✓ " : "    ")\(field.title)",
                        systemImage: field.systemImage
                    )
                }
            }
        } label: {
            Label("Customise fields", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .id(preferences.revision)
    }

    // MARK: Helpers

    private func visible(_ field: FieldKind) -> Bool {
        _ = preferences.revision
        guard state.device.descriptor.capabilities.contains(field.requiredCapability) else { return false }
        return preferences.isVisible(field, for: state.device.descriptor)
    }

    private var pollingOptions: [PollingRate] {
        let d = state.device.descriptor
        if !d.hyperPollingRates.isEmpty {
            return d.hyperPollingRates.sorted { $0.rawValue < $1.rawValue }
        }
        return [.hz125, .hz500, .hz1000]
    }

    private func formatRate(_ rate: PollingRate) -> String {
        rate.rawValue >= 1000 ? "\(rate.rawValue / 1000)k" : "\(rate.rawValue)"
    }

    private var dpiDisplay: String {
        if let x = state.dpiX, let y = state.dpiY {
            return x == y ? "\(x)" : "\(x) × \(y)"
        }
        return "—"
    }

    private var batteryPercentText: String {
        if let percent = state.batteryPercent { return "\(percent)%" }
        return "—"
    }
}

/// High-contrast pill for the "charging" state so it reads cleanly on the
/// card's light background in both light and dark appearance.
private struct ChargingPill: View {
    let compact: Bool

    private let tint: Color = Color(red: 0.92, green: 0.58, blue: 0.05) // amber, AA contrast

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            if !compact {
                Text("Plugged in")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text("Charging")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(tint)
        )
    }
}

// MARK: - Quick custom DPI

private struct QuickCustomDPI: View {
    let initial: UInt16?
    let maxDPI: Int
    let onApply: (UInt16) -> Void

    @State private var text: String = ""
    @State private var error: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Custom")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("e.g. 1234", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity)
                .onSubmit(apply)
                .onChange(of: text) { _, new in
                    let cleaned = new.filter(\.isNumber)
                    if cleaned != new { text = cleaned }
                    error = false
                }
            Button("Set") { apply() }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(text.isEmpty)
        }
        .onAppear {
            if text.isEmpty, let i = initial { text = "\(i)" }
        }
        .onChange(of: initial) { _, new in
            if let n = new { text = "\(n)" }
        }
    }

    private func apply() {
        guard let value = Int(text), value >= 100 else { error = true; return }
        let cap = maxDPI > 0 ? maxDPI : 45_000
        let clamped = UInt16(min(value, cap))
        onApply(clamped)
    }
}

// MARK: - Menu button

private struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(hovering ? DS.Palette.subtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Permission card

private struct PermissionCard: View {
    let manager: DeviceManager

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Input Monitoring required", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)

                Text("macOS blocks HID control until you grant Input Monitoring to Tiny Razer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Spacing.sm) {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Retry") {
                        Task {
                            await manager.stop()
                            await manager.start()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
