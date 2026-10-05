import SwiftUI

@main
struct KeepAliveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(delegate.store)
                .environment(delegate.renewer)
        } label: {
            MenuBarIcon(store: delegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.store)
                .environment(delegate.renewer)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    lazy var renewer = Renewer(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        renewer.start()
    }
}

private struct MenuBarIcon: View {
    let store: AppStore

    var body: some View {
        Image(systemName: store.hasProblem
              ? "exclamationmark.arrow.triangle.2.circlepath"
              : "arrow.triangle.2.circlepath")
            .accessibilityLabel("KeepAlive")
    }
}
