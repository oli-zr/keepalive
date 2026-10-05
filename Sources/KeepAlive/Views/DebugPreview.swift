#if DEBUG
import SwiftUI

/// Shows a view in a normal window with sample data, for screenshots during development.
/// Usage: KEEPALIVE_PREVIEW=menu|general|apps|device|activity swift run
@MainActor
enum DebugPreview {
    private static var window: NSWindow?

    private static var target: String? { ProcessInfo.processInfo.environment["KEEPALIVE_PREVIEW"] }

    /// KEEPALIVE_PREVIEW=window opens the real settings window with sample data.
    static var wantsWindow: Bool { target == "window" }

    static func sampleStore() -> AppStore {
        let store = AppStore(ephemeral: true)
        fillSampleData(store)
        return store
    }

    static func showIfRequested() -> Bool {
        guard let target, target != "window" else { return wantsWindow }

        let store = sampleStore()
        let renewer = Renewer(store: store)

        let content: AnyView
        switch target {
        case "menu": content = AnyView(MenuContentView())
        case "settings": content = AnyView(SettingsView())
        case "general": content = AnyView(GeneralSettingsView())
        case "apps": content = AnyView(AppsSettingsView())
        case "device": content = AnyView(DeviceSettingsView())
        default: content = AnyView(LogView())
        }

        let host = NSHostingController(rootView: content
            .frame(width: target == "menu" ? 300 : 720, height: target == "menu" ? nil : 520)
            .environment(store)
            .environment(renewer))
        let window = NSWindow(contentViewController: host)
        window.title = target
        window.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.frame.maxY ?? 900) - 80))
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        return true
    }

    private static func fillSampleData(_ store: AppStore) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var hitster = ManagedApp(name: "Hitster", projectPath: home + "/Desktop/HITST/Hitster/Hitster.xcodeproj",
                                 scheme: "Hitster", bundleIdentifier: "com.example.Hitster", productName: "Hitster.app")
        hitster.lastInstall = .now.addingTimeInterval(-2 * 86_400)
        hitster.expirationDate = .now.addingTimeInterval(5 * 86_400)
        var pulse = ManagedApp(name: "Pulse", projectPath: home + "/Desktop/spotube-master/Pulse/Pulse.xcodeproj",
                               scheme: "Pulse", bundleIdentifier: "com.example.Pulse", productName: "Pulse.app")
        pulse.lastInstall = .now.addingTimeInterval(-6 * 86_400)
        pulse.expirationDate = .now.addingTimeInterval(16 * 3600)
        var widget = ManagedApp(name: "Weather Widget", projectPath: "/tmp/Weather.xcodeproj",
                                scheme: "Weather", bundleIdentifier: "com.example.Weather", productName: "Weather.app")
        widget.isEnabled = false
        store.apps = [hitster, pulse, widget]
        store.activity[hitster.id] = .building
        store.devices = [Device(id: "1", udid: "1", name: "iPhone", model: "iPhone 16", transport: .network, isReachable: true)]
        store.preferences.deviceIdentifier = "1"
        store.preferences.deviceName = "iPhone"
        store.record("Building for iPhone…", app: "Hitster")
        store.record("Installed. Valid until 12 Oct 2026 at 21:34.", app: "Pulse")
        store.record("iPhone is not reachable. KeepAlive will try again later.", app: "Weather Widget", isError: true)
    }
}
#endif
