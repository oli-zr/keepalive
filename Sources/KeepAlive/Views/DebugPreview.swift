#if DEBUG
import SwiftUI

/// Shows a view in a normal window with sample data, for screenshots during development.
/// Usage: scripts/preview.sh menu|settings|general|apps|device|activity|window
/// `KEEPALIVE_PREVIEW=… swift run` works too, but shows the compatibility look instead of Liquid Glass.
@MainActor
enum DebugPreview {
    private static var window: NSWindow?

    nonisolated private static var target: String? { ProcessInfo.processInfo.environment["KEEPALIVE_PREVIEW"] }

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
            .environment(renewer)
            .environment(Updater(store: store))
            .environment(SettingsWindow()))
        let window = NSWindow(contentViewController: host)
        window.title = target
        window.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.frame.maxY ?? 900) - 80))
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        return true
    }

    /// Makes the settings window active, so controls show their accent color, and sizes it
    /// from KEEPALIVE_WINDOW_SIZE, for example "720x400".
    static func prepareWindowForScreenshot() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = NSApp.windows.first(where: { $0.title.isEmpty == false && $0.isVisible && $0.level == .normal }) else { return }
            if let size = ProcessInfo.processInfo.environment["KEEPALIVE_WINDOW_SIZE"]?.split(separator: "x"),
               size.count == 2, let width = Double(size[0]), let height = Double(size[1]) {
                window.setContentSize(NSSize(width: width, height: height))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// True while a preview runs; previews never talk to real devices.
    nonisolated static var isActive: Bool { target != nil }

    /// KEEPALIVE_SAMPLE_ICONS points at a folder with `<App Name>.png` files for the sample apps.
    nonisolated static func sampleIcon(for app: ManagedApp) -> NSImage? {
        guard let folder = ProcessInfo.processInfo.environment["KEEPALIVE_SAMPLE_ICONS"] else { return nil }
        return NSImage(contentsOfFile: "\(folder)/\(app.name).png")
    }

    private static func fillSampleData(_ store: AppStore) {
        let environment = ProcessInfo.processInfo.environment
        let phone = Device(id: "1", udid: "1", name: "iPhone", model: "iPhone 17 Pro", isPad: false, transport: .network, isReachable: true)
        let pad = Device(id: "2", udid: "2", name: "iPad", model: "iPad Air", isPad: true, transport: .network, isReachable: true)
        // KEEPALIVE_SAMPLE_DEVICES=1 shows a single iPhone.
        let devices = environment["KEEPALIVE_SAMPLE_DEVICES"] == "1" ? [phone] : [phone, pad]
        store.devices = devices
        store.preferences.devices = devices.map(SavedDevice.init)

        func sample(_ name: String, installed days: Double?, at hour: Double = 10, excluding excluded: Set<Device.ID> = []) -> ManagedApp {
            let id = name.replacingOccurrences(of: " ", with: "")
            var app = ManagedApp(name: name, projectPath: "/Projects/\(id)/\(id).xcodeproj", scheme: id,
                                 bundleIdentifier: "com.example.\(id)", productName: "\(id).app")
            app.excludedDevices = excluded
            if let days {
                let midnight = Calendar.current.startOfDay(for: .now)
                let installed = midnight.addingTimeInterval(-days.rounded(.down) * 86_400 + hour * 3600)
                for device in devices where !excluded.contains(device.id) {
                    app.installations[device.id] = Installation(lastInstall: installed, expirationDate: installed.addingTimeInterval(7 * 86_400))
                }
            }
            return app
        }
        let trail = sample("Trail Log", installed: 1, at: 9.25)
        let synth = sample("Pocket Synth", installed: 3, at: 19.7)
        let notes = sample("Field Notes", installed: 2, at: 8.1, excluding: [pad.id])
        store.apps = [trail, synth, notes]
        // KEEPALIVE_SAMPLE_IDLE shows every app at rest, for the menu screenshot.
        if environment["KEEPALIVE_SAMPLE_IDLE"] == nil {
            store.activity[synth.id] = .building
        }
        // A believable history: each app was renewed a few days apart.
        func entries(_ app: ManagedApp) -> [LogEntry] {
            let targets = store.targets(for: app)
            let installation = app.installation(on: phone.id)
            let date = (installation.lastInstall ?? .now).addingTimeInterval(-60)
            let until = installation.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
            let names = targets.map(\.name).formatted(.list(type: .and).locale(.interface))
            return [LogEntry(date: date, app: app.name, message: "Building for \(names)…", isError: false)]
                + targets.enumerated().map { index, device in
                    LogEntry(date: date.addingTimeInterval(Double(index + 1) * 60), app: app.name,
                             message: "Installed on \(device.name). Valid until \(until).", isError: false)
                }
        }
        store.log = [synth, notes, trail].flatMap(entries)
    }
}
#endif
