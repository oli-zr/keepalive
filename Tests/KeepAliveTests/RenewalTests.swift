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

    @Test("Looks for an iPhone that was away without waiting an hour")
    func unreachableRetry() {
        var away = app(installedDaysAgo: 5)
        away.lastError = "iPhone is not reachable."
        away.lastAttempt = now.addingTimeInterval(-10 * 60)
        away.isWaitingForDevice = true
        #expect(renewer.isDue(away, now: now))
    }
}

@MainActor
@Suite("Renewal queue")
struct QueueTests {
    let store = AppStore(ephemeral: true)

    func addApps(_ count: Int) -> [ManagedApp.ID] {
        (0..<count).map { index in
            let app = ManagedApp(name: "App \(index)", projectPath: "/tmp/App\(index).xcodeproj", scheme: "App",
                                 bundleIdentifier: "com.example.App\(index)", productName: "App.app")
            store.apps.append(app)
            return app.id
        }
    }

    /// A renewer whose first renewal works like a long build that stops when cancelled.
    func renewer(recording started: Started, slow: ManagedApp.ID) -> Renewer {
        let renewer = Renewer(store: store)
        renewer.renewal = { id in
            started.ids.append(id)
            if id == slow { try? await Task.sleep(for: .seconds(60)) }
        }
        return renewer
    }

    @MainActor
    final class Started {
        var ids: [ManagedApp.ID] = []

        func waitForFirst() async {
            while ids.isEmpty { await Task.yield() }
        }
    }

    @Test("Stopping resets the apps that were still waiting")
    func cancelResetsWaitingApps() async {
        let ids = addApps(3)
        let started = Started()
        let renewer = renewer(recording: started, slow: ids[0])

        renewer.renew(ids)
        await started.waitForFirst()
        #expect(store.activity[ids[1]] == .waiting)

        renewer.cancelAll()
        await renewer.waitUntilFinished()
        #expect(started.ids == [ids[0]])
        #expect(!store.isBusy)
    }

    @Test("Apps requested right after stopping are still renewed")
    func renewAfterCancel() async {
        let ids = addApps(3)
        let started = Started()
        let renewer = renewer(recording: started, slow: ids[0])

        renewer.renew([ids[0], ids[1]])
        await started.waitForFirst()
        renewer.cancelAll()
        renewer.renew([ids[2]])

        await renewer.waitUntilFinished()
        #expect(started.ids == [ids[0], ids[2]])
        #expect(!store.isBusy)
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
        #expect(!app.isWaitingForDevice)
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
