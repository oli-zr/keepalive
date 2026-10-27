import Foundation
import Testing
@testable import KeepAlive

@MainActor
@Suite("When apps are renewed")
struct SchedulingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = AppStore(ephemeral: true)
    var renewer: Renewer { Renewer(store: store) }
    let phone = SavedDevice(id: "PHONE", name: "iPhone")
    let pad = SavedDevice(id: "PAD", name: "iPad", isPad: true)

    init() {
        store.preferences.devices = [phone]
        // Due devices would otherwise depend on whether this Mac runs on battery.
        store.preferences.onlyOnPower = false
    }

    func installation(installedDaysAgo days: Double?, expiresInHours hours: Double? = nil) -> Installation {
        guard let days else { return Installation() }
        return Installation(
            lastInstall: now.addingTimeInterval(-days * 86_400),
            expirationDate: now.addingTimeInterval((hours ?? (7 - days) * 24) * 3600)
        )
    }

    func app(installedDaysAgo days: Double?, expiresInHours hours: Double? = nil) -> ManagedApp {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcodeproj", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        app.installations[phone.id] = installation(installedDaysAgo: days, expiresInHours: hours)
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
        #expect(renewer.dueDevices(for: paused, now: now).isEmpty)
    }

    @Test("Waits an hour after a failed attempt")
    func retryDelay() {
        var failed = app(installedDaysAgo: 5)
        failed.installations[phone.id]?.lastError = "Build failed"
        failed.installations[phone.id]?.lastAttempt = now.addingTimeInterval(-10 * 60)
        #expect(!renewer.isDue(failed, now: now))

        failed.installations[phone.id]?.lastAttempt = now.addingTimeInterval(-61 * 60)
        #expect(renewer.isDue(failed, now: now))
    }

    @Test("Looks for a device that was away without waiting an hour")
    func unreachableRetry() {
        var away = app(installedDaysAgo: 5)
        away.installations[phone.id]?.lastError = "iPhone is not reachable."
        away.installations[phone.id]?.lastAttempt = now.addingTimeInterval(-10 * 60)
        away.installations[phone.id]?.isWaitingForDevice = true
        #expect(renewer.isDue(away, now: now))
    }

    @Test("Renews only on the devices where the app is due")
    func dueDevices() {
        store.preferences.devices = [phone, pad]
        var app = app(installedDaysAgo: 1)
        app.installations[pad.id] = installation(installedDaysAgo: 4)
        #expect(renewer.isDue(app, now: now))
        #expect(renewer.dueDevices(for: app, now: now) == [pad])
    }

    @Test("A newly chosen device gets every app")
    func newDevice() {
        let app = app(installedDaysAgo: 1)
        #expect(!renewer.isDue(app, now: now))
        store.preferences.devices.append(pad)
        #expect(renewer.dueDevices(for: app, now: now) == [pad])
    }

    @Test("Leaves out devices turned off for the app")
    func excludedDevice() {
        store.preferences.devices = [phone, pad]
        var app = app(installedDaysAgo: 1)
        app.excludedDevices = [pad.id]
        #expect(store.targets(for: app) == [phone])
        #expect(!renewer.isDue(app, now: now))
    }

    @Test("Without a device, nothing is due and the menu bar shows a problem")
    func noDevice() {
        store.preferences.devices = []
        let app = app(installedDaysAgo: nil)
        store.apps = [app]
        #expect(!renewer.isDue(app, now: now))
        #expect(store.hasProblem)
    }

    @Test("Two devices with the same name are told apart by their model")
    func sameName() {
        store.preferences.devices = [
            SavedDevice(id: "A", name: "iPhone", model: "iPhone 16"),
            SavedDevice(id: "B", name: "iPhone", model: "iPhone 13 mini"),
            SavedDevice(id: "C", name: "iPad", model: "iPad Air", isPad: true),
        ]
        #expect(store.chosenDevices.map(\.name) == ["iPhone (iPhone 16)", "iPhone (iPhone 13 mini)", "iPad"])

        var app = app(installedDaysAgo: 1)
        app.excludedDevices = ["A"]
        #expect(store.targets(for: app).map(\.name) == ["iPhone (iPhone 13 mini)", "iPad"])
    }

    @Test("A problem on any device shows in the menu bar")
    func problemOnOneDevice() {
        store.preferences.devices = [phone, pad]
        var app = app(installedDaysAgo: 1)
        app.installations[pad.id] = Installation(lastError: "iPad is not reachable.", isWaitingForDevice: true)
        store.apps = [app]
        #expect(store.hasProblem)

        store.apps[0].excludedDevices = [pad.id]
        #expect(!store.hasProblem)
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
    let phone = SavedDevice(id: "PHONE", name: "iPhone")
    let pad = SavedDevice(id: "PAD", name: "iPad", isPad: true)

    func app(expiresInHours hours: Double?, enabled: Bool = true, error: String? = nil) -> ManagedApp {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcodeproj", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        app.installations[phone.id] = Installation(expirationDate: hours.map { now.addingTimeInterval($0 * 3600) }, lastError: error)
        app.isEnabled = enabled
        return app
    }

    func status(_ app: ManagedApp, on targets: [SavedDevice]? = nil, activity: Activity = .idle) -> AppStatus {
        AppStatus(app: app, targets: targets ?? [phone], activity: activity, now: now)
    }

    @Test("Shows what is happening right now", arguments: [
        (Activity.waiting, "Waiting…"), (.preparing, "Looking for iPhone…"),
        (.building, "Building…"), (.installing(on: "iPhone"), "Installing…"),
    ])
    func activity(activity: Activity, text: String) {
        #expect(status(app(expiresInHours: 100), activity: activity).text == text)
    }

    @Test("Names the device being worked on when there are several")
    func activityWithSeveralDevices() {
        let app = app(expiresInHours: 100)
        #expect(status(app, on: [phone, pad], activity: .preparing).text == "Looking for devices…")
        #expect(status(app, on: [phone, pad], activity: .installing(on: "iPad")).text == "Installing on iPad…")
    }

    @Test("Marks expired apps as a failure")
    func expired() {
        let status = status(app(expiresInHours: -1))
        #expect(status.text == "Expired")
        #expect(status.tone == .failure)
    }

    @Test("Warns when an app expires within a day")
    func soon() {
        #expect(status(app(expiresInHours: 5)).tone == .warning)
        #expect(status(app(expiresInHours: 50)).tone == .normal)
    }

    @Test("Shows the last error")
    func error() {
        let status = status(app(expiresInHours: 50, error: "Build failed"))
        #expect(status.text == "Build failed")
        #expect(status.tone == .failure)
    }

    @Test("Shows paused and new apps")
    func pausedAndNew() {
        #expect(status(app(expiresInHours: 50, enabled: false)).text == "Paused")
        #expect(status(app(expiresInHours: nil)).text == "Not installed yet")
    }

    @Test("Asks for a device when none is chosen")
    func noDevice() {
        let status = status(app(expiresInHours: nil), on: [])
        #expect(status.text == "No device selected")
        #expect(status.tone == .failure)
        #expect(self.status(app(expiresInHours: nil, enabled: false), on: []).text == "Paused")
    }

    @Test("Tells when an app is turned off on every chosen device")
    func turnedOffEverywhere() {
        var app = app(expiresInHours: nil)
        app.excludedDevices = [phone.id]
        let status = status(app, on: [])
        #expect(status.text == "No device turned on")
        #expect(status.tone == .failure)
    }

    @Test("With several devices, shows the one that needs attention first")
    func severalDevices() {
        var app = app(expiresInHours: 100)
        app.installations[pad.id] = Installation(expirationDate: now.addingTimeInterval(-3600))
        let expired = status(app, on: [phone, pad])
        #expect(expired.text == "Expired on iPad")
        #expect(expired.tone == .failure)
        #expect(expired.details.components(separatedBy: "\n") == ["iPhone: Expires in 4 days", "iPad: Expired"])

        app.installations[pad.id] = Installation()
        #expect(status(app, on: [phone, pad]).text == "Not installed on iPad yet")

        app.installations[pad.id] = Installation(expirationDate: now.addingTimeInterval(5 * 3600))
        let soon = status(app, on: [phone, pad])
        #expect(soon.text == "iPad: expires in 5 hours")
        #expect(soon.tone == .warning)

        app.installations[pad.id] = Installation(expirationDate: now.addingTimeInterval(50 * 3600))
        #expect(status(app, on: [phone, pad]).text == "Expires in 2 days")
    }

    @Test("Does not name a device when all are in the same state")
    func sharedState() {
        var app = app(expiresInHours: nil)
        app.installations[pad.id] = Installation()
        #expect(status(app, on: [phone, pad]).text == "Not installed yet")
    }

    @Test("Shows an error that already names its device as it is")
    func deviceError() {
        var app = app(expiresInHours: 100)
        app.installations[pad.id] = Installation(lastError: "iPad is not reachable.", isWaitingForDevice: true)
        let status = status(app, on: [phone, pad])
        #expect(status.text == "iPad is not reachable.")
        #expect(status.details.components(separatedBy: "\n").last == "iPad is not reachable.")
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
        #expect(preferences.devices.isEmpty)
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
        #expect(app.installations.isEmpty)
        #expect(app.excludedDevices.isEmpty)
    }

    @Test("Settings from version 1.2 move to the device they were made for")
    func singleDeviceSettings() throws {
        let json = Data("""
            {"preferences":{"deviceIdentifier":"PHONE-1","deviceName":"Work iPhone","renewAfterDays":3},
             "apps":[{"id":"6F1F6E4A-1C8B-4E52-9A43-0B8E0E4C2F11","name":"App","projectPath":"/tmp/App.xcodeproj",
                      "scheme":"App","bundleIdentifier":"com.example.App","productName":"App.app",
                      "lastInstall":"2026-10-20T10:00:00Z","expirationDate":"2026-10-27T10:00:00Z",
                      "lastError":"Work iPhone is not reachable.","isWaitingForDevice":true}]}
            """.utf8)
        struct Stored: Decodable {
            let preferences: Preferences
            let apps: [ManagedApp]
        }
        #expect(Preferences.legacyDevice(in: json) == "PHONE-1")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.legacyDevice] = "PHONE-1"
        let stored = try decoder.decode(Stored.self, from: json)

        #expect(stored.preferences.devices == [SavedDevice(id: "PHONE-1", name: "Work iPhone")])
        let installation = try #require(stored.apps.first?.installations["PHONE-1"])
        #expect(installation.lastInstall == ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z"))
        #expect(installation.expirationDate == ISO8601DateFormatter().date(from: "2026-10-27T10:00:00Z"))
        #expect(installation.lastError == "Work iPhone is not reachable.")
        #expect(installation.isWaitingForDevice)
    }

    @Test("Apps survive a round trip")
    func roundTrip() throws {
        var app = ManagedApp(name: "App", projectPath: "/tmp/App.xcworkspace", scheme: "App",
                             bundleIdentifier: "com.example.App", productName: "App.app")
        app.preBuildCommand = "flutter build ios --config-only"
        app.excludedDevices = ["PAD"]
        app.installations["PHONE"] = Installation(lastInstall: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(ManagedApp.self, from: JSONEncoder().encode(app))
        #expect(decoded == app)
        #expect(decoded.isWorkspace)
        #expect(Preferences.legacyDevice(in: try JSONEncoder().encode(["preferences": Preferences()])) == nil)
    }
}
