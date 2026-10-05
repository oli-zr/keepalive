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

        Window("KeepAlive", id: SettingsView.windowID) {
            SettingsView()
                .environment(delegate.store)
                .environment(delegate.renewer)
        }
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    let store = DebugPreview.wantsWindow ? DebugPreview.sampleStore() : AppStore()
    #else
    let store = AppStore()
    #endif
    lazy var renewer = Renewer(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugPreview.showIfRequested() { return }
        #endif
        renewer.start()
    }
}

private struct MenuBarIcon: View {
    let store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: store.hasProblem
              ? "exclamationmark.arrow.triangle.2.circlepath"
              : "arrow.triangle.2.circlepath")
            .accessibilityLabel("KeepAlive")
            #if DEBUG
            .task {
                guard DebugPreview.wantsWindow else { return }
                openWindow(id: SettingsView.windowID)
                DebugPreview.prepareWindowForScreenshot()
            }
            #endif
    }
}
