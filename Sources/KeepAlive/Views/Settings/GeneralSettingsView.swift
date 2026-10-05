import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled || Self.isPreview

    private static var isPreview: Bool {
        #if DEBUG
        return DebugPreview.isActive
        #else
        return false
        #endif
    }
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Stepper(value: $store.preferences.renewAfterDays, in: 1...6) {
                    Text("Renew after \(store.preferences.renewAfterDays) days")
                }
                Toggle("Only Build While Connected to Power", isOn: $store.preferences.onlyOnPower)
            } header: {
                Text("Renewal")
            } footer: {
                Text("Apps signed with a free Apple Account stop opening after seven days. KeepAlive renews them early, whenever your iPhone is on the same network. Apps that expire within a day are renewed on battery power too.")
                    .settingsFooter()
            }

            Section {
                LabeledContent("Xcode") {
                    HStack(spacing: 8) {
                        Text(xcodeDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if store.preferences.xcodePath != nil {
                            Button("Use Default") { store.preferences.xcodePath = nil }
                        }
                        Button("Choose…", action: chooseXcode)
                    }
                }
            } header: {
                Text("Developer Tools")
            }
        }
        .formStyle(.grouped)
    }

    private var xcodeDescription: String {
        guard let toolchain = try? Toolchain.resolve(override: store.preferences.xcodePath) else {
            return String(localized: "Not Found")
        }
        return toolchain.xcodeAppPath
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseXcode() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if Toolchain.developerDirectory(forXcodeAt: url.path) != nil {
            store.preferences.xcodePath = url.path
        } else {
            NSSound.beep()
        }
    }
}

extension View {
    /// Footer text in grouped forms, styled like System Settings.
    func settingsFooter() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
