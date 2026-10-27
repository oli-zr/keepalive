import SwiftUI

struct DeviceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Renewer.self) private var renewer
    @State private var isRefreshing = false

    /// Paired devices, followed by chosen ones that `devicectl` does not list right now.
    private var rows: [DeviceRow.Model] {
        let paired = store.devices.map { DeviceRow.Model(saved: SavedDevice($0), live: $0) }
        let missing = store.preferences.devices
            .filter { saved in !store.devices.contains { $0.id == saved.id } }
            .map { DeviceRow.Model(saved: $0, live: nil) }
        return paired + missing
    }

    var body: some View {
        Form {
            Section {
                if rows.isEmpty {
                    Text(isRefreshing ? LocalizedStringKey("Searching…") : LocalizedStringKey("No paired iPhone or iPad found."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        DeviceRow(model: row, isOn: binding(for: row.saved))
                    }
                }
            } header: {
                HStack {
                    Text("Paired Devices")
                    Spacer()
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Refresh")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KeepAlive installs your apps on every device that is turned on. On a device that is turned off, they stay installed but are no longer renewed. To choose devices for a single app, open its details under Apps.")
                    Text("To renew over Wi‑Fi, connect your iPhone or iPad to this Mac with a cable once. Then open Xcode, choose Window → Devices and Simulators, and select “Connect via network”.")
                }
                .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func binding(for device: SavedDevice) -> Binding<Bool> {
        Binding(
            get: { store.preferences.devices.contains { $0.id == device.id } },
            set: { isOn in
                if isOn {
                    guard !store.preferences.devices.contains(where: { $0.id == device.id }) else { return }
                    store.preferences.devices.append(device)
                    // Bring the apps to the new device without waiting for the next check.
                    Task { await renewer.checkDueApps() }
                } else {
                    store.preferences.devices.removeAll { $0.id == device.id }
                }
            }
        )
    }

    private func refresh() async {
        isRefreshing = true
        await renewer.refreshDevices()
        isRefreshing = false
    }
}

private struct DeviceRow: View {
    struct Model: Identifiable {
        let saved: SavedDevice
        let live: Device?

        var id: Device.ID { saved.id }
    }

    let model: Model
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.saved.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.saved.name)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(model.saved.name, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var subtitle: String {
        guard let live = model.live else { return String(localized: "Not reachable") }
        return live.model.isEmpty ? live.connectionDescription : "\(live.model) · \(live.connectionDescription)"
    }
}
