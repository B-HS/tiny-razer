import SwiftUI
import RazerKit

enum SettingsSelection: Hashable {
    case general
    case device(UInt64)
}

struct SettingsScene: View {
    @Bindable var manager: DeviceManager
    @Bindable var preferences: FieldPreferences
    @Bindable var launchAtLogin: LaunchAtLogin
    @State private var selection: SettingsSelection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 440)
        .ignoresSafeArea()
        .onChange(of: manager.devices.map(\.id)) { _, ids in
            if case .device(let id) = selection, !ids.contains(id) {
                selection = .general
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 36) // traffic-light clearance

            sidebarSection(title: "App") {
                sidebarButton(
                    label: "General",
                    systemImage: "gearshape.fill",
                    tint: .accentColor,
                    isSelected: selection == .general,
                    action: { selection = .general }
                )
            }

            sidebarSection(title: "Devices") {
                if manager.devices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "computermouse")
                            .foregroundStyle(.secondary)
                        Text("No devices")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                } else {
                    ForEach(manager.devices) { state in
                        DeviceSidebarRow(
                            state: state,
                            isSelected: selection == .device(state.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selection = .device(state.id) }
                    }
                }
            }

            Spacer()
        }
    }

    private func sidebarSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            VStack(spacing: 2) {
                content()
            }
            .padding(.horizontal, 8)
        }
    }

    private func sidebarButton(
        label: String,
        systemImage: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView(launchAtLogin: launchAtLogin)
        case .device(let id):
            if let state = manager.devices.first(where: { $0.id == id }) {
                DeviceDetail(state: state, manager: manager, preferences: preferences)
            } else {
                ContentUnavailableView(
                    "Device disconnected",
                    systemImage: "cable.connector.slash",
                    description: Text("Reconnect the device or pick another entry in the sidebar.")
                )
            }
        }
    }
}

// MARK: - Sidebar row

private struct DeviceSidebarRow: View {
    let state: DeviceState
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: IconForCategory.symbol(for: state.device.category, filled: true))
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : IconForCategory.accentColor(for: state.device.category))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.shortName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.device.descriptor.isWireless ? Color.blue : Color.green)
                        .frame(width: 5, height: 5)
                        .opacity(isSelected ? 0.9 : 1.0)
                    Text(state.device.descriptor.isWireless ? "Wireless" : "Wired")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                    if let battery = state.batteryPercent {
                        Text("·").foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.6))
                        Text("\(battery)%")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

// MARK: - Detail

private struct DeviceDetail: View {
    let state: DeviceState
    let manager: DeviceManager
    let preferences: FieldPreferences

    @State private var dpiValue: Double = 800
    @State private var customDPIX: String = "800"
    @State private var customDPIY: String = "800"
    @State private var linkXY: Bool = true
    @State private var customDPIError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                compactHero

                if visible(.battery), state.device.supports(.battery) {
                    batteryCard
                }

                if visible(.dpi), state.device.supports(.dpi) {
                    dpiCard
                }

                if state.device.supports(.dpiStages) {
                    dpiStagesCard
                }

                if hasAnyLEDCapability {
                    lightingCard
                }

                if state.device.supports(.brightness) {
                    brightnessCard
                }

                if state.device.supports(.idleTimer) || state.device.supports(.lowBatteryThreshold) {
                    powerCard
                }

                // Polling rate + Fields visibility share a row on wide windows.
                let showPolling = visible(.pollingRate) && state.device.supports(.pollingRate)
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    if showPolling {
                        pollingCard
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    fieldsVisibilityCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                aboutCard
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let x = state.dpiX { dpiValue = Double(x); customDPIX = "\(x)" }
            if let y = state.dpiY { customDPIY = "\(y)" }
        }
        .onChange(of: state.dpiX) { _, new in
            if let n = new { dpiValue = Double(n); customDPIX = "\(n)" }
        }
        .onChange(of: state.dpiY) { _, new in
            if let n = new { customDPIY = "\(n)" }
        }
    }

    // MARK: Compact hero

    private var compactHero: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(IconForCategory.accentColor(for: state.device.category).opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: IconForCategory.symbol(for: state.device.category, filled: true))
                    .font(.system(size: 18))
                    .foregroundStyle(IconForCategory.accentColor(for: state.device.category))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayName)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    badge(state.device.descriptor.isWireless ? "Wireless" : "Wired",
                          color: state.device.descriptor.isWireless ? .blue : .green)
                    if state.device.descriptor.maxDPI > 0 {
                        badge("Up to \(state.device.descriptor.maxDPI / 1000)k DPI", color: .secondary)
                    }
                }
            }

            Spacer()

            if state.device.supports(.battery) {
                BatteryRing(
                    percent: state.batteryPercent ?? 0,
                    isCharging: state.isCharging ?? false,
                    size: 34,
                    placeholder: state.batteryPercent == nil
                )
            }

            Button {
                Task { await manager.readStateNow(for: state.id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh device state")
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: DPI

    private var dpiCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Label("DPI", systemImage: "scope")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(dpiReadout)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                let maxDPI = max(state.device.descriptor.maxDPI, 3200)
                Slider(value: $dpiValue, in: 100...Double(maxDPI), step: 100)
                    .onChange(of: dpiValue) { _, newValue in
                        if linkXY {
                            customDPIX = "\(Int(newValue))"
                            customDPIY = "\(Int(newValue))"
                        } else {
                            customDPIX = "\(Int(newValue))"
                        }
                    }

                HStack {
                    Text("\(Int(dpiValue)) DPI")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Button("Apply") {
                        let value = UInt16(dpiValue)
                        Task { await manager.setDPI(x: value, y: value, for: state.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Divider()

                // Presets
                HStack(spacing: 6) {
                    Text("Presets")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach([400, 800, 1600, 3200, 6400], id: \.self) { preset in
                        Button("\(preset)") {
                            dpiValue = Double(preset)
                            customDPIX = "\(preset)"
                            customDPIY = "\(preset)"
                            let value = UInt16(preset)
                            Task { await manager.setDPI(x: value, y: value, for: state.id) }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Custom input
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Custom")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle(isOn: $linkXY) {
                            Label("Link X & Y", systemImage: linkXY ? "link" : "link.badge.plus")
                                .font(.system(size: 10))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: linkXY) { _, newLinked in
                            if newLinked {
                                customDPIY = customDPIX
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        dpiField(label: "X", text: $customDPIX, isPrimary: true)
                        Text("×")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        dpiField(label: "Y", text: $customDPIY, isPrimary: false)
                            .disabled(linkXY)
                            .opacity(linkXY ? 0.5 : 1.0)
                        Spacer()
                        Button("Apply") {
                            applyCustomDPI()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                    }

                    if let err = customDPIError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func dpiField(label: String, text: Binding<String>, isPrimary: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("DPI", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .monospacedDigit()
                .onChange(of: text.wrappedValue) { _, newValue in
                    // Strip non-digits
                    let cleaned = newValue.filter(\.isNumber)
                    if cleaned != newValue {
                        text.wrappedValue = cleaned
                        return
                    }
                    if isPrimary && linkXY {
                        customDPIY = cleaned
                    }
                }
        }
    }

    private func applyCustomDPI() {
        customDPIError = nil
        guard let xInt = Int(customDPIX), let yInt = Int(customDPIY) else {
            customDPIError = "Enter numeric X and Y values."
            return
        }
        let maxDPI = state.device.descriptor.maxDPI > 0 ? state.device.descriptor.maxDPI : 45_000
        guard (100...maxDPI).contains(xInt), (100...maxDPI).contains(yInt) else {
            customDPIError = "Values must be between 100 and \(maxDPI)."
            return
        }
        let x = UInt16(xInt)
        let y = UInt16(yInt)
        dpiValue = Double(xInt)
        Task { await manager.setDPI(x: x, y: y, for: state.id) }
    }

    private var dpiReadout: String {
        if let x = state.dpiX, let y = state.dpiY {
            return "\(x) × \(y)"
        }
        return "—"
    }

    // MARK: Polling

    private var pollingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Polling rate", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    ForEach(pollingOptions, id: \.self) { rate in
                        Button {
                            Task { await manager.setPollingRate(rate, for: state.id) }
                        } label: {
                            Text(formatRate(rate))
                                .font(.system(size: 12, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text("Higher rates reduce input latency, use more battery.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Battery

    private var batteryCard: some View {
        Card {
            HStack(spacing: DS.Spacing.md) {
                BatteryRing(
                    percent: state.batteryPercent ?? 0,
                    isCharging: state.isCharging ?? false,
                    size: 56,
                    placeholder: state.batteryPercent == nil
                )

                VStack(alignment: .leading, spacing: 3) {
                    Label("Battery", systemImage: "battery.75")
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.batteryPercent.map { "\($0)%" } ?? "Reading…")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.batteryPercent == nil ? .secondary : .primary)
                    if let charging = state.isCharging {
                        Label(charging ? "Charging" : "On battery",
                              systemImage: charging ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(charging ? .yellow : .secondary)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: DPI stages

    private var dpiStagesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Label("DPI stages", systemImage: "dial.medium.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let stages = state.dpiStages {
                        Text("Active: \(stages.activeStage)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if let stages = state.dpiStages {
                    VStack(spacing: 4) {
                        ForEach(Array(stages.stages.enumerated()), id: \.offset) { i, stage in
                            HStack {
                                Text("Stage \(i + 1)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text("\(stage.x) × \(stage.y)")
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                if UInt8(i + 1) == stages.activeStage {
                                    Text("Active")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                } else {
                                    Button("Activate") {
                                        Task { await manager.setDPIStages(stages.stages, activeStage: UInt8(i + 1), for: state.id) }
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                } else {
                    Text("Reading stages…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text("Cycle through stored DPI presets using the DPI clutch button on the mouse.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Lighting

    private var hasAnyLEDCapability: Bool {
        state.device.supports(.rgbStatic) ||
        state.device.supports(.rgbSpectrum) ||
        state.device.supports(.rgbBreathe) ||
        state.device.supports(.rgbWave) ||
        state.device.supports(.rgbReactive) ||
        state.device.supports(.rgbStarlight)
    }

    private var lightingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Lighting", systemImage: "light.max")
                    .font(.system(size: 13, weight: .semibold))

                LightingPicker(state: state, manager: manager)
            }
        }
    }

    // MARK: Brightness

    private var brightnessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Label("Brightness", systemImage: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(state.brightness.map { "\(Int(Double($0) / 255.0 * 100))%" } ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                BrightnessSlider(state: state, manager: manager)
            }
        }
    }

    // MARK: Power (idle + low battery)

    private var powerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Power", systemImage: "bolt.horizontal.fill")
                    .font(.system(size: 13, weight: .semibold))

                if state.device.supports(.idleTimer) {
                    IdleTimerRow(state: state, manager: manager)
                }
                if state.device.supports(.lowBatteryThreshold) {
                    LowBatteryRow(state: state, manager: manager)
                }
            }
        }
    }

    // MARK: About

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Device info", systemImage: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                infoRow("Firmware", value: state.firmwareVersion ?? "—")
                infoRow("Serial", value: state.serialNumber?.isEmpty == false ? state.serialNumber! : "—")
                infoRow("Product ID", value: String(format: "0x%04X", state.device.handle.productID))
                infoRow("Transaction ID", value: String(format: "0x%02X", state.device.descriptor.transactionID.rawValue))
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: Fields visibility card

    private var fieldsVisibilityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Fields", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))

                Text("Choose which rows appear in the menu bar and here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                ForEach(preferences.availableFields(for: state.device.descriptor)) { field in
                    Toggle(isOn: Binding(
                        get: {
                            _ = preferences.revision
                            return preferences.isVisible(field, for: state.device.descriptor)
                        },
                        set: { _ in preferences.toggle(field, for: state.device.descriptor) }
                    )) {
                        Label(field.title, systemImage: field.systemImage)
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: Helpers

    private func visible(_ field: FieldKind) -> Bool {
        _ = preferences.revision
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
        rate.rawValue >= 1000 ? "\(rate.rawValue / 1000)k Hz" : "\(rate.rawValue) Hz"
    }
}
