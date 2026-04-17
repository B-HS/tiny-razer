import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var launchAtLogin: LaunchAtLogin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header

                startupCard

                aboutCard
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("General")
                    .font(.system(size: 14, weight: .semibold))
                Text("App-wide preferences")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var startupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Startup", systemImage: "power")
                    .font(.system(size: 13, weight: .semibold))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at Login")
                            .font(.system(size: 12, weight: .medium))
                        Text("Start Tiny Razer automatically when you log in to your Mac.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                if launchAtLogin.requiresApproval {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Needs approval in System Settings → General → Login Items.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("About", systemImage: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                labelRow("Version", value: versionString)
                labelRow("Bundle ID", value: bundleID)
                labelRow("License", value: "GPL-2.0")
                HStack {
                    Link("GitHub", destination: URL(string: "https://github.com/B-HS/tiny-razer")!)
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labelRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "—"
    }
}
