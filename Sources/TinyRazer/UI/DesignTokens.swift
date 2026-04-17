import SwiftUI

/// Design language tokens for Tiny Razer UI. Keep everything in one place so
/// tweaking spacing/radius/color propagates consistently.
enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    enum Palette {
        static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.6)
        static let cardStroke = Color.primary.opacity(0.08)
        static let subtle = Color.primary.opacity(0.05)
        static let accent = Color.accentColor
    }
}

// MARK: - Card container

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(DS.Spacing.md)
            .background(DS.Palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Palette.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

// MARK: - Battery ring

struct BatteryRing: View {
    let percent: Int
    let isCharging: Bool
    var size: CGFloat = 40
    /// When true, renders a muted "no reading yet" placeholder instead of 0%.
    var placeholder: Bool = false

    private var tint: Color {
        if placeholder { return .secondary }
        if isCharging { return .yellow }
        switch percent {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(placeholder ? 0.12 : 0.18), lineWidth: 3)

            if !placeholder {
                Circle()
                    .trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: percent)
            }

            VStack(spacing: 0) {
                if placeholder {
                    Text("—")
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .foregroundStyle(.yellow)
                } else {
                    Text("\(percent)")
                        .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preset chip row

struct PresetChips<Value: Hashable>: View {
    let values: [Value]
    let selected: Value?
    let label: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text(label(value))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(chipBackground(isSelected: value == selected))
                        .foregroundStyle(value == selected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                DS.Palette.accent
            } else {
                DS.Palette.subtle
            }
        }
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let title: String
    let systemImage: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
