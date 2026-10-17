import SwiftUI
import UserNotifications

@main
struct KeepAliveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(delegate.store)
                .environment(delegate.renewer)
                .environment(delegate.updater)
                .environment(delegate.settingsWindow)
        } label: {
            MenuBarIcon(store: delegate.store, settingsWindow: delegate.settingsWindow)
        }
        .menuBarExtraStyle(.window)

        Window("KeepAlive", id: SettingsView.windowID) {
            SettingsView()
                .environment(delegate.store)
                .environment(delegate.renewer)
                .environment(delegate.updater)
                .environment(delegate.settingsWindow)
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
    lazy var updater = Updater(store: store)
    let settingsWindow = SettingsWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugPreview.showIfRequested() { return }
        #endif
        if Notifier.isAvailable { UNUserNotificationCenter.current().delegate = self }
        renewer.start()
        updater.start()
    }

    /// Handles a click on a notification or one of its buttons.
    private func handle(action: String, appID: ManagedApp.ID?) {
        switch action {
        case Notifier.Action.renew.rawValue:
            if let appID { renewer.renew([appID]) }
        case Notifier.Action.showActivity.rawValue, UNNotificationDefaultActionIdentifier:
            settingsWindow.show(.activity)
        default:
            break
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let appID = (response.notification.request.content.userInfo[Notifier.appKey] as? String).flatMap(UUID.init)
        await handle(action: action, appID: appID)
    }

    /// Shows notifications even while the settings window is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private struct MenuBarIcon: View {
    let store: AppStore
    let settingsWindow: SettingsWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: store.hasProblem
              ? "exclamationmark.arrow.triangle.2.circlepath"
              : "arrow.triangle.2.circlepath")
            .accessibilityLabel("KeepAlive")
            .onAppear { settingsWindow.openWindow = openWindow }
            #if DEBUG
            .task {
                guard DebugPreview.wantsWindow else { return }
                openWindow(id: SettingsView.windowID)
                DebugPreview.prepareWindowForScreenshot()
            }
            #endif
    }
}
