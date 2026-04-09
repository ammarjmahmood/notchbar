import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Storage Folder
            settingRow(label: "Storage Folder", icon: "folder") {
                HStack(spacing: 8) {
                    Text(abbreviatePath(settings.storageFolderPath))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Change") {
                        pickFolder { path in
                            settings.storageFolderPath = path
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            // Screenshot Watch Folder
            settingRow(label: "Screenshot Folder", icon: "camera") {
                HStack(spacing: 8) {
                    Text(abbreviatePath(settings.screenshotFolderPath))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Change") {
                        pickFolder { path in
                            settings.screenshotFolderPath = path
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            // Auto-clear timer
            settingRow(label: "Auto-Clear", icon: "timer") {
                HStack(spacing: 8) {
                    Stepper(value: $settings.autoClearMinutes, in: 1...60) {
                        Text("\(settings.autoClearMinutes) min")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .labelsHidden()
                    Text("\(settings.autoClearMinutes) min")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Launch at Login
            settingRow(label: "Launch at Login", icon: "power") {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func settingRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 110, alignment: .leading)

            content()

            Spacer()
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func pickFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url.path)
            }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.08), in: Capsule())
    }
}
