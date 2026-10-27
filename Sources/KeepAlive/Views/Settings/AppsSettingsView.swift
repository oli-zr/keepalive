import SwiftUI
import UniformTypeIdentifiers

struct AppsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorTarget?

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                if store.apps.isEmpty {
                    Text("No apps yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.apps) { $app in
                    HStack(spacing: 10) {
                        AppIconView(app: app, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            let status = store.status(for: app)
                            (Text(status.text).foregroundStyle(status.style) + devicesNote(for: app))
                                .font(.callout)
                                .lineLimit(1)
                                .help(status.details)
                        }
                        Spacer()
                        Toggle("Renew Automatically", isOn: $app.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Button {
                            editor = .edit(app.id)
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Details")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…", action: chooseProject)
                }
            } footer: {
                Text("A free Apple Account can have up to three of your own apps installed on a device at the same time.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in
            AppEditorView(target: target)
        }
    }

    /// Names the devices of an app that is not on all of them, for example “· only on iPhone”.
    private func devicesNote(for app: ManagedApp) -> Text {
        let targets = store.targets(for: app)
        guard !targets.isEmpty, targets.count < store.chosenDevices.count else { return Text(verbatim: "") }
        let names = targets.map(\.name).formatted(.list(type: .and).locale(.interface))
        return Text(verbatim: " · ").foregroundStyle(.secondary) + Text("only on \(names)").foregroundStyle(.secondary)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose an Xcode project, a workspace or the folder that contains it.")
        panel.prompt = String(localized: "Add")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = ["xcodeproj", "xcworkspace"].compactMap { UTType(filenameExtension: $0) } + [.folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let project = BuildService.resolveProject(at: url) {
            editor = .add(project)
        } else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No Xcode Project Found")
            alert.informativeText = String(localized: "The selected folder does not contain an .xcodeproj or .xcworkspace.")
            alert.runModal()
        }
    }
}

enum EditorTarget: Identifiable {
    case add(URL)
    case edit(ManagedApp.ID)

    var id: String {
        switch self {
        case .add(let url): "add-\(url.path)"
        case .edit(let id): "edit-\(id)"
        }
    }
}

private struct AppEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(Renewer.self) private var renewer
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget

    @State private var draft: ManagedApp?
    @State private var schemes: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var confirmsRemoval = false

    private var isNew: Bool {
        if case .add = target { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let draft {
                    details(for: draft)
                } else if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Reading project…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !isNew {
                    Button("Remove App…", role: .destructive) { confirmsRemoval = true }
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? LocalizedStringKey("Add") : LocalizedStringKey("Done"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil || isLoading)
            }
            .padding(16)
        }
        .frame(width: 480)
        .task { await load() }
        .confirmationDialog(
            "Remove \(draft?.name ?? "")?",
            isPresented: $confirmsRemoval
        ) {
            Button("Remove", role: .destructive) {
                if case .edit(let id) = target { store.remove(id) }
                dismiss()
            }
        } message: {
            Text("The app stays on your devices, but KeepAlive will stop renewing it.")
        }
    }

    @ViewBuilder
    private func details(for app: ManagedApp) -> some View {
        Section {
            HStack(spacing: 12) {
                AppIconView(app: app, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: binding(\.name))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                    Text(app.bundleIdentifier)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        }

        Section {
            LabeledContent("Project") {
                HStack(spacing: 6) {
                    Text(app.projectURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([app.projectURL])
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Show in Finder")
                }
            }
            Picker("Scheme", selection: Binding(
                get: { app.scheme },
                set: { scheme in Task { await select(scheme: scheme) } }
            )) {
                ForEach(schemes.contains(app.scheme) ? schemes : [app.scheme] + schemes, id: \.self) { scheme in
                    Text(scheme).tag(scheme)
                }
            }
            LabeledContent("Configuration", value: "Release")
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }

        if showsDevices(for: app) {
            Section {
                let devices = store.chosenDevices
                let onCount = devices.filter { !app.excludedDevices.contains($0.id) }.count
                ForEach(devices) { device in
                    let isOn = !app.excludedDevices.contains(device.id)
                    AppDeviceRow(
                        device: device,
                        app: store.app(app.id) ?? app,
                        showsStatus: !isNew,
                        // The last device stays on; “Renew Automatically” pauses the app instead.
                        isLocked: isOn && onCount == 1,
                        isOn: Binding(
                            get: { !app.excludedDevices.contains(device.id) },
                            set: { isOn in
                                if isOn { draft?.excludedDevices.remove(device.id) } else { draft?.excludedDevices.insert(device.id) }
                            }
                        )
                    )
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("On a device that is turned off, the app stays installed but is no longer renewed.")
                    .settingsFooter()
            }
        }

        Section {
            TextField("Before Build", text: binding(\.preBuildCommand), prompt: Text(verbatim: "flutter build ios --release --config-only"))
                .font(.system(.body, design: .monospaced))
        } footer: {
            Text("Optional. Runs in the project folder before each build, for example to prepare a Flutter project.")
                .settingsFooter()
        }

        Section {
            Toggle("Renew Automatically", isOn: binding(\.isEnabled))
            if !isNew && !showsDevices(for: app) {
                LabeledContent("Status") {
                    // The saved app, so the status follows a renewal while the sheet is open.
                    Text(store.status(for: store.app(app.id) ?? app).text)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let device = store.chosenDevices.first,
                   let installed = (store.app(app.id) ?? app).installation(on: device.id).lastInstall {
                    LabeledContent("Last Renewed") {
                        Text(installed, format: .dateTime.weekday(.wide).day().month().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// With one device there is nothing to choose, unless the app was turned off for it
    /// while there were several.
    private func showsDevices(for app: ManagedApp) -> Bool {
        let devices = store.chosenDevices
        return devices.count > 1 || devices.contains { app.excludedDevices.contains($0.id) }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ManagedApp, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Loading

    private var service: BuildService? {
        (try? Toolchain.resolve(override: store.preferences.xcodePath)).map(BuildService.init)
    }

    private func load() async {
        switch target {
        case .edit(let id):
            draft = store.app(id)
            if let draft, let info = try? await service?.inspect(projectAt: draft.projectURL) {
                schemes = info.schemes
            }
        case .add(let url):
            guard let service else {
                errorMessage = ToolchainError.xcodeNotFound.localizedDescription
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let info = try await service.inspect(projectAt: url)
                schemes = info.schemes
                let scheme = preferredScheme(in: info.schemes, project: url)
                guard let scheme else { throw BuildError.noApplicationTarget }
                let settings = try await service.inspect(scheme: scheme, projectAt: url)
                let app = ManagedApp(
                    name: settings.displayName,
                    projectPath: url.path,
                    scheme: scheme,
                    bundleIdentifier: settings.bundleIdentifier,
                    productName: settings.productName
                )
                IconLocator.cacheIcon(for: app)
                draft = app
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Prefers the scheme named like the project, which is what Xcode creates by default.
    private func preferredScheme(in schemes: [String], project: URL) -> String? {
        let name = project.deletingPathExtension().lastPathComponent
        return schemes.first { $0 == name } ?? schemes.first
    }

    private func select(scheme: String) async {
        guard var app = draft, let service else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let settings = try await service.inspect(scheme: scheme, projectAt: app.projectURL)
            app.scheme = scheme
            app.bundleIdentifier = settings.bundleIdentifier
            app.productName = settings.productName
            draft = app
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let draft else { return }
        if isNew {
            store.apps.append(draft)
            store.record(String(localized: "Added."), app: draft.name)
            Task { await renewer.checkDueApps() }
        } else {
            // Copy only what the sheet edits; a renewal may have updated the status meanwhile.
            store.update(draft.id) {
                $0.name = draft.name
                $0.scheme = draft.scheme
                $0.bundleIdentifier = draft.bundleIdentifier
                $0.productName = draft.productName
                $0.preBuildCommand = draft.preBuildCommand
                $0.isEnabled = draft.isEnabled
                $0.excludedDevices = draft.excludedDevices
            }
            // A device that was turned on may need the app right away.
            Task { await renewer.checkDueApps() }
        }
        dismiss()
    }
}

/// One device in the app's details: whether the app is installed there, and how it is doing.
private struct AppDeviceRow: View {
    let device: SavedDevice
    /// The saved app, so the status follows a renewal while the sheet is open.
    let app: ManagedApp
    let showsStatus: Bool
    let isLocked: Bool
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                if showsStatus && isOn.wrappedValue {
                    let installation = app.installation(on: device.id)
                    let status = AppStatus(installation: installation, isEnabled: app.isEnabled)
                    Text(status.text)
                        .font(.callout)
                        .foregroundStyle(status.style)
                        .fixedSize(horizontal: false, vertical: true)
                    if let installed = installation.lastInstall {
                        Text("Last renewed \(installed.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle(device.name, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isLocked)
        }
    }
}
