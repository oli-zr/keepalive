import SwiftUI

struct DeviceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Renewer.self) private var renewer
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section {
                if store.devices.isEmpty {
                    Text(isRefreshing ? LocalizedStringKey("Searching…") : LocalizedStringKey("No paired iPhone found."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.devices) { device in
                        DeviceRow(device: device, isSelected: device.id == store.preferences.deviceIdentifier) {
                            store.preferences.deviceIdentifier = device.id
                            store.preferences.deviceName = device.name
                        }
                    }
                }
            } header: {
                HStack {
                    Text("iPhone")
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
                Text("To renew over Wi‑Fi, connect your iPhone to this Mac with a cable once. Then open Xcode, choose Window → Devices and Simulators, and select “Connect via network”.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func refresh() async {
        isRefreshing = true
        await renewer.refreshDevices()
        isRefreshing = false
    }
}

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                    Text(device.model.isEmpty ? device.connectionDescription : "\(device.model) · \(device.connectionDescription)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
