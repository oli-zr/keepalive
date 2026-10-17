import AppKit
import Network
import Observation
import UserNotifications

/// Decides when apps are renewed and runs renewals one at a time.
///
/// Checks are scheduled through `NSBackgroundActivityScheduler`, which lets macOS
/// coalesce them with other background work, and run again after the Mac wakes or
/// joins a network. A check only reads the saved state; `devicectl` and `xcodebuild`
/// run only when an app is actually due.
@MainActor
@Observable
final class Renewer {
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var queue: [ManagedApp.ID] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var hasSeenNetwork = false
    @ObservationIgnored private var networkCheck: Task<Void, Never>?
    /// Renews one app. Tests replace it, so the queue can be checked without Xcode.
    @ObservationIgnored var renewal: ((ManagedApp.ID) async -> Void)?

    nonisolated static let retryInterval: TimeInterval = 60 * 60
    nonisolated static let urgentInterval: TimeInterval = 24 * 60 * 60
    /// How long to wait after a network change before looking for the iPhone.
    nonisolated static let networkSettleDelay: Duration = .seconds(30)

    init(store: AppStore) {
        self.store = store
    }

    func start() {
        let scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "KeepAlive").check")
        scheduler.repeats = true
        scheduler.interval = 30 * 60
        scheduler.tolerance = 15 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.checkDueApps()
                completion(.finished)
            }
        }
        self.scheduler = scheduler

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Give Wi‑Fi a moment to reconnect before looking for the iPhone.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(90))
                await self?.checkDueApps()
            }
        }

        // Joining a network, for example at home, is a good moment to look for the iPhone.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(isOnline: isOnline) }
        }
        monitor.start(queue: .main)
        networkMonitor = monitor

        Notifier.requestAuthorization()
        Task {
            try? await Task.sleep(for: .seconds(10))
            await checkDueApps()
        }
    }

    // MARK: - Public actions

    /// Renews the given apps right away, regardless of schedule or power source.
    func renew(_ ids: [ManagedApp.ID]) {
        enqueue(ids)
    }

    func renewAll() {
        enqueue(store.apps.filter(\.isEnabled).map(\.id))
    }

    func cancelAll() {
        for id in queue { store.activity[id] = .idle }
        queue.removeAll()
        worker?.cancel()
    }

    /// Returns once no renewal is running or waiting.
    func waitUntilFinished() async {
        while let worker { await worker.value }
    }

    func refreshDevices() async {
        #if DEBUG
        if DebugPreview.isActive { return }
        #endif
        guard let toolchain = try? Toolchain.resolve(override: store.preferences.xcodePath) else { return }
        do {
            store.devices = try await DeviceService(toolchain: toolchain).devices()
            store.lastDeviceRefresh = .now
            selectOnlyDeviceIfNeeded()
        } catch is CancellationError {
            // The view that asked for the refresh went away.
        } catch {
            store.record(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Scheduling

    func isDue(_ app: ManagedApp, now: Date = .now) -> Bool {
        guard app.isEnabled else { return false }
        // Looking for an iPhone that was away is cheap, so only real failures wait.
        if app.lastError != nil, !app.isWaitingForDevice, let attempt = app.lastAttempt, now.timeIntervalSince(attempt) < Self.retryInterval {
            return false
        }
        guard let installed = app.lastInstall else { return true }
        if let expiration = app.expirationDate, expiration.timeIntervalSince(now) < Self.urgentInterval { return true }
        return now.timeIntervalSince(installed) >= Double(store.preferences.renewAfterDays) * 86_400
    }

    private func isUrgent(_ app: ManagedApp, now: Date) -> Bool {
        guard let expiration = app.expirationDate else { return false }
        return expiration.timeIntervalSince(now) < Self.urgentInterval
    }

    func checkDueApps() async {
        let now = Date.now
        warnAboutExpiringApps(now: now)

        var due = store.apps.filter { isDue($0, now: now) && !store.activity(for: $0).isBusy }
        if store.preferences.onlyOnPower && !PowerState.isOnExternalPower {
            due = due.filter { isUrgent($0, now: now) }
        }
        guard !due.isEmpty else { return }
        enqueue(due.map(\.id))
    }

    private func networkChanged(isOnline: Bool) {
        // The monitor reports the current network once when it starts.
        guard hasSeenNetwork else {
            hasSeenNetwork = true
            return
        }
        guard isOnline else { return }
        networkCheck?.cancel()
        networkCheck = Task {
            // Networks often report several changes in a row while connecting.
            try? await Task.sleep(for: Self.networkSettleDelay)
            guard !Task.isCancelled else { return }
            await checkDueApps()
        }
    }

    private func enqueue(_ ids: [ManagedApp.ID]) {
        for id in ids where store.app(id) != nil && !queue.contains(id) && !store.activity[id, default: .idle].isBusy {
            queue.append(id)
            store.activity[id] = .waiting
        }
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task {
            while !queue.isEmpty, !Task.isCancelled {
                let id = queue.removeFirst()
                if let renewal { await renewal(id) } else { await renewOne(id) }
                store.activity[id] = .idle
            }
            worker = nil
            // cancelAll() empties the queue, so anything in it now was added afterwards.
            startWorkerIfNeeded()
        }
    }

    // MARK: - Renewal

    private func renewOne(_ id: ManagedApp.ID) async {
        guard let app = store.app(id) else { return }
        defer {
            // Builds are only needed until the app is on the iPhone. Keeping them would
            // duplicate Xcode's own build folder, a few hundred MB per app.
            BuildService.removeBuildFiles(for: app)
        }
        store.activity[id] = .preparing

        do {
            let toolchain = try Toolchain.resolve(override: store.preferences.xcodePath)
            let device = try await reachableDevice(toolchain: toolchain)

            store.record(String(localized: "Building for \(device.name)…"), app: app.name)
            store.update(id) { $0.lastAttempt = .now }
            store.activity[id] = .building

            let buildLog = BuildLog(url: AppStore.buildLogURL(for: app))
            let product = try await BuildService(toolchain: toolchain).build(app) { buildLog.write($0) }
            let profile = ProfileInspector.embeddedProfile(inApp: product)
            IconLocator.cacheIcon(for: app, builtApp: product)

            store.activity[id] = .installing
            try await DeviceService(toolchain: toolchain).install(appAt: product, on: device) { buildLog.write($0) }
            buildLog.close()

            store.update(id) {
                $0.lastInstall = .now
                $0.expirationDate = profile?.expirationDate
                $0.lastError = nil
                $0.isWaitingForDevice = false
            }
            let until = profile?.expirationDate.formatted(date: .abbreviated, time: .shortened) ?? "–"
            store.record(String(localized: "Installed. Valid until \(until)."), app: app.name)
        } catch is CancellationError {
            store.record(String(localized: "Cancelled."), app: app.name)
        } catch {
            let message = error.localizedDescription
            let isNewProblem = message != app.lastError
            let isUnreachable = if case RenewError.deviceUnreachable = error { true } else { false }
            store.update(id) {
                $0.lastError = message
                $0.isWaitingForDevice = isUnreachable
            }
            store.record(message, app: app.name, isError: true)
            // An iPhone that is away is normal and covered by the expiry warning;
            // only new, real failures deserve a notification.
            if isNewProblem && !isUnreachable {
                Notifier.post(
                    title: String(localized: "\(app.name) could not be renewed"),
                    body: message,
                    kind: .failure,
                    app: id
                )
            }
        }
    }

    private func reachableDevice(toolchain: Toolchain) async throws -> Device {
        store.devices = (try? await DeviceService(toolchain: toolchain).devices()) ?? []
        store.lastDeviceRefresh = .now
        selectOnlyDeviceIfNeeded()
        guard let device = store.selectedDevice else {
            if store.preferences.deviceIdentifier == nil { throw RenewError.noDeviceSelected }
            throw RenewError.deviceUnreachable(store.preferences.deviceName ?? "iPhone")
        }
        guard device.isReachable else { throw RenewError.deviceUnreachable(device.name) }
        return device
    }

    private func selectOnlyDeviceIfNeeded() {
        guard store.preferences.deviceIdentifier == nil, store.devices.count == 1, let only = store.devices.first else { return }
        store.preferences.deviceIdentifier = only.id
        store.preferences.deviceName = only.name
    }

    private func warnAboutExpiringApps(now: Date) {
        for app in store.apps where app.isEnabled {
            guard let expiration = app.expirationDate,
                  isUrgent(app, now: now),
                  expiration > now,
                  app.warnedExpiration != expiration
            else { continue }
            store.update(app.id) { $0.warnedExpiration = expiration }
            Notifier.post(
                title: String(localized: "\(app.name) expires soon"),
                body: String(localized: "Connect your iPhone to the same Wi‑Fi as this Mac so KeepAlive can renew it."),
                kind: .expiry,
                app: app.id
            )
        }
    }
}

enum RenewError: LocalizedError {
    case noDeviceSelected
    case deviceUnreachable(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return String(localized: "No iPhone selected. Choose one in Settings → Device.")
        case .deviceUnreachable(let name):
            return String(localized: "\(name) is not reachable. KeepAlive will try again later.")
        }
    }
}

/// Writes the full tool output of one renewal to a file in ~/Library/Logs/KeepAlive.
private final class BuildLog: @unchecked Sendable {
    private let handle: FileHandle?
    private let lock = NSLock()

    init(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        handle?.write(Data((line + "\n").utf8))
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
    }

    deinit { try? handle?.close() }
}

enum Notifier {
    /// Decides which buttons a notification offers.
    enum Kind: String {
        case failure = "renewal-failed"
        case expiry = "expires-soon"
    }

    enum Action: String {
        case renew
        case showActivity = "show-activity"
    }

    /// The `userInfo` key that holds the app's ID.
    static let appKey = "app"

    /// Notifications need a real app bundle; `swift run` has none.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let renew = UNNotificationAction(identifier: Action.renew.rawValue, title: String(localized: "Renew Now"))
        let showActivity = UNNotificationAction(
            identifier: Action.showActivity.rawValue,
            title: String(localized: "Show Activity"),
            options: .foreground
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Kind.failure.rawValue, actions: [renew, showActivity], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.expiry.rawValue, actions: [renew], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, kind: Kind? = nil, app: ManagedApp.ID? = nil) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let kind { content.categoryIdentifier = kind.rawValue }
        if let app { content.userInfo = [appKey: app.uuidString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
