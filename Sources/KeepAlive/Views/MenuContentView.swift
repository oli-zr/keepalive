import SwiftUI

struct MenuContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(Renewer.self) private var renewer
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.apps.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(store.apps) { app in
                        AppRowView(app: app)
                    }
                }
                .padding(.horizontal, 5)
            }

            MenuDivider()

            VStack(spacing: 0) {
                if store.isBusy {
                    MenuButton("Stop Renewing") { renewer.cancelAll() }
                } else {
                    MenuButton("Renew All Now") { renewer.renewAll() }
                        .disabled(!store.apps.contains(where: \.isEnabled))
                }
                MenuButton("Settings…") { showSettings() }
            }
            .padding(.horizontal, 5)

            MenuDivider()

            MenuButton("Quit KeepAlive") { NSApp.terminate(nil) }
                .padding(.horizontal, 5)
        }
        .padding(.bottom, 5)
        .frame(width: 300)
        .task { await renewer.refreshDevices() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("KeepAlive")
                .font(.headline)
            Spacer()
            Text(deviceLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 7)
    }

    private var deviceLine: String {
        if let device = store.selectedDevice {
            return device.isReachable ? device.name : String(localized: "\(device.name) · Not reachable")
        }
        if let name = store.preferences.deviceName {
            return String(localized: "\(name) · Not reachable")
        }
        return String(localized: "No iPhone selected")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Apps")
                .font(.subheadline.weight(.semibold))
            Text("Add an Xcode project to keep it installed on your iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct AppRowView: View {
    @Environment(AppStore.self) private var store
    @Environment(Renewer.self) private var renewer
    let app: ManagedApp
    @State private var isHovering = false

    var body: some View {
        let activity = store.activity(for: app)
        let status = AppStatus(app: app, activity: activity)

        HStack(spacing: 10) {
            AppIconView(app: app, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                Text(status.text)
                    .font(.subheadline)
                    .foregroundStyle(status.style)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(status.text)

            Spacer(minLength: 4)

            if activity.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if isHovering && app.isEnabled {
                Button {
                    renewer.renew([app.id])
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Renew Now")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .onHover { isHovering = $0 }
    }
}

/// A full-width menu item with the hover highlight used in system menu bar extras.
struct MenuButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering && isEnabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .onHover { isHovering = $0 }
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }
}
