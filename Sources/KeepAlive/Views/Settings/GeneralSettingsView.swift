import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Updater.self) private var updater
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled || Self.isPreview
    @State private var loginItemError: String?

    private static var isPreview: Bool {
        #if DEBUG
        return DebugPreview.isActive
        #else
        return false
        #endif
    }

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
                Toggle("Check for Updates Automatically", isOn: $store.preferences.checksForUpdates)
                Toggle("Install Updates Automatically", isOn: $store.preferences.installsUpdates)
                    .disabled(!store.preferences.checksForUpdates)
                LabeledContent {
                    HStack(spacing: 8) {
                        if updater.state == .checking {
                            ProgressView().controlSize(.small)
                        }
                        if let release = updater.availableRelease {
                            let version = release.version.description
                            Button {
                                updater.install(release)
                            } label: {
                                Text(updater.canInstallInPlace
                                     ? LocalizedStringKey("Install \(version)")
                                     : LocalizedStringKey("Download \(version)"))
                            }
                            .disabled(updater.state != .available(release))
                        } else {
                            Button("Check Now") { Task { await updater.checkNow() } }
                                .disabled(updater.state == .checking)
                        }
                    }
                } label: {
                    Text("Version \(AppVersion.current.description)")
                    Text(updateStatus)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates are installed while no app is being built. Your apps and settings are kept.")
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

    private var updateStatus: String {
        switch updater.state {
        case .idle:
            guard let date = store.preferences.lastUpdateCheck else { return String(localized: "Not checked yet") }
            return String(localized: "Last checked \(date.formatted(.relative(presentation: .named)))")
        case .checking: return String(localized: "Checking…")
        case .upToDate: return String(localized: "KeepAlive is up to date.")
        case .available(let release): return String(localized: "Version \(release.version.description) is available.")
        case .downloading: return String(localized: "Downloading…")
        case .installing: return String(localized: "Installing…")
        case .failed(let message): return message
        }
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
