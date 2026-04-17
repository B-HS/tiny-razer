import SwiftUI
import RazerKit

/// Effect + color picker for the device's primary LED zone.
/// Renders the set of effects the device's capabilities actually support and
/// exposes relevant secondary controls (color well, speed, wave direction).
struct LightingPicker: View {
    let state: DeviceState
    let manager: DeviceManager

    @State private var selected: EffectKind = .static
    @State private var color: Color = .red
    @State private var secondColor: Color = .blue
    @State private var speed: EffectSpeed = .medium
    @State private var direction: WaveDirection = .left

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 4) {
                ForEach(availableEffects, id: \.self) { kind in
                    Button {
                        selected = kind
                        applyIfImmediate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 11))
                            Text(kind.label)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(selected == kind ? Color.accentColor : DS.Palette.subtle)
                        )
                        .foregroundStyle(selected == kind ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Secondary controls depending on effect
            Group {
                switch selected {
                case .off, .spectrum, .breathingRandom:
                    EmptyView()
                case .static, .breathingSingle, .reactive, .starlightSingle:
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 50, height: 24)
                case .breathingDual, .starlightDual:
                    HStack {
                        ColorPicker("Color 1", selection: $color, supportsOpacity: false).labelsHidden()
                        ColorPicker("Color 2", selection: $secondColor, supportsOpacity: false).labelsHidden()
                    }
                    .frame(height: 24)
                case .wave:
                    Picker("Direction", selection: $direction) {
                        Text("Left").tag(WaveDirection.left)
                        Text("Right").tag(WaveDirection.right)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                case .starlightRandom:
                    EmptyView()
                }
            }

            if selected.needsSpeed {
                Picker("Speed", selection: $speed) {
                    Text("Fastest").tag(EffectSpeed.fastest)
                    Text("Fast").tag(EffectSpeed.fast)
                    Text("Medium").tag(EffectSpeed.medium)
                    if selected.allowsSlow { Text("Slow").tag(EffectSpeed.slow) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            HStack {
                Spacer()
                Button("Apply") { applyNow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .onChange(of: color) { _, _ in applyIfImmediate() }
        .onChange(of: secondColor) { _, _ in applyIfImmediate() }
        .onChange(of: speed) { _, _ in applyIfImmediate() }
        .onChange(of: direction) { _, _ in applyIfImmediate() }
    }

    private var availableEffects: [EffectKind] {
        var kinds: [EffectKind] = [.off]
        if state.device.supports(.rgbStatic) { kinds.append(.static) }
        if state.device.supports(.rgbSpectrum) { kinds.append(.spectrum) }
        if state.device.supports(.rgbWave) { kinds.append(.wave) }
        if state.device.supports(.rgbReactive) { kinds.append(.reactive) }
        if state.device.supports(.rgbBreathe) {
            kinds.append(contentsOf: [.breathingSingle, .breathingDual, .breathingRandom])
        }
        if state.device.supports(.rgbStarlight) {
            kinds.append(contentsOf: [.starlightSingle, .starlightDual, .starlightRandom])
        }
        return kinds
    }

    private func applyIfImmediate() {
        // Effects without parameters get applied on select; parameterised ones
        // wait for Apply to avoid spam-writing while the user drags sliders.
        if !selected.hasParameters { applyNow() }
    }

    private func applyNow() {
        let rgb1 = color.razerRGB
        let rgb2 = secondColor.razerRGB
        let effect: LEDEffect = {
            switch selected {
            case .off: return .off
            case .static: return .static(rgb1)
            case .spectrum: return .spectrum
            case .wave: return .wave(direction)
            case .reactive: return .reactive(speed: speed, color: rgb1)
            case .breathingSingle: return .breathingSingle(rgb1)
            case .breathingDual: return .breathingDual(rgb1, rgb2)
            case .breathingRandom: return .breathingRandom
            case .starlightSingle: return .starlightSingle(speed: speed, color: rgb1)
            case .starlightDual: return .starlightDual(speed: speed, rgb1, rgb2)
            case .starlightRandom: return .starlightRandom(speed: speed)
            }
        }()
        Task { await manager.setLEDEffect(effect, for: state.id) }
    }

    enum EffectKind: String, Hashable {
        case off, `static`, spectrum, wave, reactive
        case breathingSingle, breathingDual, breathingRandom
        case starlightSingle, starlightDual, starlightRandom

        var label: String {
            switch self {
            case .off: return "Off"
            case .static: return "Static"
            case .spectrum: return "Spectrum"
            case .wave: return "Wave"
            case .reactive: return "Reactive"
            case .breathingSingle: return "Breathe"
            case .breathingDual: return "Breathe 2"
            case .breathingRandom: return "Breathe R"
            case .starlightSingle: return "Starlight"
            case .starlightDual: return "Starlight 2"
            case .starlightRandom: return "Starlight R"
            }
        }

        var symbol: String {
            switch self {
            case .off: return "moon"
            case .static: return "circle.fill"
            case .spectrum: return "rainbow"
            case .wave: return "waveform"
            case .reactive: return "hand.tap"
            case .breathingSingle, .breathingDual, .breathingRandom: return "wind"
            case .starlightSingle, .starlightDual, .starlightRandom: return "sparkle"
            }
        }

        var hasParameters: Bool {
            switch self {
            case .off, .spectrum, .breathingRandom, .starlightRandom: return false
            default: return true
            }
        }

        var needsSpeed: Bool {
            switch self {
            case .reactive, .starlightSingle, .starlightDual, .starlightRandom: return true
            default: return false
            }
        }

        var allowsSlow: Bool {
            self == .reactive  // reactive accepts 1..4, starlight only 1..3
        }
    }
}

struct BrightnessSlider: View {
    let state: DeviceState
    let manager: DeviceManager
    @State private var value: Double = 0

    var body: some View {
        Slider(value: $value, in: 0...255, step: 1) { editing in
            if !editing {
                Task { await manager.setBrightness(UInt8(value), for: state.id) }
            }
        }
        .onAppear {
            if let b = state.brightness { value = Double(b) }
        }
        .onChange(of: state.brightness) { _, new in
            if let n = new { value = Double(n) }
        }
    }
}

struct IdleTimerRow: View {
    let state: DeviceState
    let manager: DeviceManager

    var body: some View {
        HStack {
            Text("Idle timeout")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach([60, 180, 300, 600, 900], id: \.self) { seconds in
                    Button("\(seconds / 60)m") {
                        Task { await manager.setIdleTime(seconds: UInt16(seconds), for: state.id) }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .tint(state.idleTimeSeconds == UInt16(seconds) ? .accentColor : .secondary)
                }
            }
        }
    }
}

struct LowBatteryRow: View {
    let state: DeviceState
    let manager: DeviceManager

    var body: some View {
        HStack {
            Text("Low battery warning")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach([5, 15, 25], id: \.self) { pct in
                    Button("\(pct)%") {
                        Task { await manager.setLowBatteryThreshold(percent: pct, for: state.id) }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .tint(isCloseTo(state.lowBatteryThresholdPercent, pct) ? .accentColor : .secondary)
                }
            }
        }
    }

    private func isCloseTo(_ a: Int?, _ b: Int) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= 2
    }
}

private extension Color {
    /// Convert a SwiftUI Color to the 8-bit per channel RGB format used by
    /// the Razer protocol. Falls back to neutral grey if the color isn't
    /// resolvable (display-P3 / catalog colors).
    var razerRGB: RazerRGB {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = UInt8(clamping: Int((ns.redComponent * 255).rounded()))
        let g = UInt8(clamping: Int((ns.greenComponent * 255).rounded()))
        let b = UInt8(clamping: Int((ns.blueComponent * 255).rounded()))
        return RazerRGB(r: r, g: g, b: b)
    }
}
