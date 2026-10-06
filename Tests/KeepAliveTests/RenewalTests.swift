import Foundation
import Testing
@testable import KeepAlive

@MainActor
@Suite("When apps are renewed")
struct SchedulingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = AppStore(ephemeral: true)
    var renewer: Renewer { Renewer(store: store) }

    func app(installedDaysAgo days: Double?, expiresInHours hours: Double? = nil) -> ManagedApp {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcodeproj", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        if let days {
            app.lastInstall = now.addingTimeInterval(-days * 86_400)
            app.expirationDate = now.addingTimeInterval((hours ?? (7 - days) * 24) * 3600)
        }
        return app
    }

    @Test("A new app is renewed right away")
    func newApp() {
        #expect(renewer.isDue(app(installedDaysAgo: nil), now: now))
    }

    @Test("Waits until the configured number of days has passed", arguments: [
        (1.0, false), (2.9, false), (3.0, true), (5.0, true),
    ])
    func threshold(days: Double, due: Bool) {
        #expect(renewer.isDue(app(installedDaysAgo: days), now: now) == due)
    }

    @Test("Follows a changed threshold")
    func customThreshold() {
        store.preferences.renewAfterDays = 1
        #expect(renewer.isDue(app(installedDaysAgo: 1.5), now: now))
    }

    @Test("Renews early when the app expires within a day")
    func urgent() {
        #expect(renewer.isDue(app(installedDaysAgo: 0.5, expiresInHours: 20), now: now))
    }

    @Test("Never renews paused apps")
    func paused() {
        var paused = app(installedDaysAgo: 6)
        paused.isEnabled = false
        #expect(!renewer.isDue(paused, now: now))
    }

    @Test("Waits an hour after a failed attempt")
    func retryDelay() {
        var failed = app(installedDaysAgo: 5)
        failed.lastError = "Build failed"
        failed.lastAttempt = now.addingTimeInterval(-10 * 60)
        #expect(!renewer.isDue(failed, now: now))

        failed.lastAttempt = now.addingTimeInterval(-61 * 60)
        #expect(renewer.isDue(failed, now: now))
    }
}

@MainActor
@Suite("Status texts")
struct StatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func app(expiresInHours hours: Double?, enabled: Bool = true, error: String? = nil) -> ManagedApp {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcodeproj", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        app.expirationDate = hours.map { now.addingTimeInterval($0 * 3600) }
        app.isEnabled = enabled
        app.lastError = error
        return app
    }

    @Test("Shows what is happening right now", arguments: [
        (Activity.waiting, "Waiting…"), (.preparing, "Looking for iPhone…"),
        (.building, "Building…"), (.installing, "Installing…"),
    ])
    func activity(activity: Activity, text: String) {
        #expect(AppStatus(app: app(expiresInHours: 100), activity: activity, now: now).text == text)
    }

    @Test("Marks expired apps as a failure")
    func expired() {
        let status = AppStatus(app: app(expiresInHours: -1), activity: .idle, now: now)
        #expect(status.text == "Expired")
        #expect(status.tone == .failure)
    }

    @Test("Warns when an app expires within a day")
    func soon() {
        #expect(AppStatus(app: app(expiresInHours: 5), activity: .idle, now: now).tone == .warning)
        #expect(AppStatus(app: app(expiresInHours: 50), activity: .idle, now: now).tone == .normal)
    }

    @Test("Shows the last error")
    func error() {
        let status = AppStatus(app: app(expiresInHours: 50, error: "Build failed"), activity: .idle, now: now)
        #expect(status.text == "Build failed")
        #expect(status.tone == .failure)
    }

    @Test("Shows paused and new apps")
    func pausedAndNew() {
        #expect(AppStatus(app: app(expiresInHours: 50, enabled: false), activity: .idle, now: now).text == "Paused")
        #expect(AppStatus(app: app(expiresInHours: nil), activity: .idle, now: now).text == "Not installed yet")
    }
}

@Suite("Saved settings")
struct SettingsDecodingTests {
    @Test("Settings from older versions still load, with defaults for new options")
    func olderPreferences() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"renewAfterDays": 4}"#.utf8))
        #expect(preferences.renewAfterDays == 4)
        #expect(preferences.onlyOnPower)
        #expect(preferences.checksForUpdates)
        #expect(preferences.installsUpdates)
        #expect(preferences.deviceIdentifier == nil)
    }

    @Test("Apps saved without optional fields still load")
    func olderApp() throws {
        let json = """
            {"id":"6F1F6E4A-1C8B-4E52-9A43-0B8E0E4C2F11","name":"App","projectPath":"/tmp/App.xcodeproj",
             "scheme":"App","bundleIdentifier":"com.example.App","productName":"App.app"}
            """
        let app = try JSONDecoder().decode(ManagedApp.self, from: Data(json.utf8))
        #expect(app.isEnabled)
        #expect(app.preBuildCommand.isEmpty)
        #expect(app.lastInstall == nil)
    }

    @Test("Apps survive a round trip")
    func roundTrip() throws {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcworkspace", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        app.preBuildCommand = "flutter build ios --config-only"
        app.lastInstall = Date(timeIntervalSince1970: 1_800_000_000)
        let decoded = try JSONDecoder().decode(ManagedApp.self, from: JSONEncoder().encode(app))
        #expect(decoded == app)
        #expect(decoded.isWorkspace)
    }
}
