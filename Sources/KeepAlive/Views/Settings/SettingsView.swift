import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, apps, device, activity

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .apps: "Apps"
        case .device: "Device"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .apps: "square.grid.2x2.fill"
        case .device: "iphone"
        case .activity: "clock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .apps: .blue
        case .device: .green
        case .activity: .orange
        }
    }
}

/// Settings window laid out like System Settings: a sidebar with tinted icons and a grouped form.
struct SettingsView: View {
    static let windowID = "settings"

    @State private var navigation = SettingsNavigation()

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            // Like System Settings, the sidebar is always visible.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // The stack makes the column swap its content when the pane changes;
            // without it macOS 27 keeps showing the first pane's form.
            NavigationStack {
                SettingsDetail(navigation: navigation)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

/// Holds the selected pane. The detail column reads it in its own view, because the
/// split view does not re-run its detail closure when a plain state value changes.
@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane? = SettingsNavigation.initialPane

    private static var initialPane: SettingsPane {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KEEPALIVE_PANE"], let pane = SettingsPane(rawValue: name) {
            return pane
        }
        #endif
        return .general
    }
}

private struct SettingsDetail: View {
    let navigation: SettingsNavigation

    var body: some View {
        let pane = navigation.pane ?? .general
        Group {
            switch pane {
            case .general: GeneralSettingsView()
            case .apps: AppsSettingsView()
            case .device: DeviceSettingsView()
            case .activity: LogView()
            }
        }
        .navigationTitle(pane.title)
    }
}

/// The small rounded, tinted icon used in the System Settings sidebar.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
