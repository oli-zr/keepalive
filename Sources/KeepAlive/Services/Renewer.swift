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
    /// Apps the user asked to renew now, on all their devices instead of only where they are due.
    @ObservationIgnored private var forced: Set<ManagedApp.ID> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var hasSeenNetwork = false
    @ObservationIgnored private var networkCheck: Task<Void, Never>?
    /// Renews one app. Tests replace it, so the queue can be checked without Xcode.
    @ObservationIgnored var renewal: ((ManagedApp.ID) async -> Void)?

    nonisolated static let retryInterval: TimeInterval = 60 * 60
    nonisolated static let urgentInterval: TimeInterval = 24 * 60 * 60
    /// How long to wait after a network change before looking for devices.
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
            // Give Wi‑Fi a moment to reconnect before looking for devices.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(90))
                await self?.checkDueApps()
            }
        }

        // Joining a network, for example at home, is a good moment to look for devices.
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

    /// Renews the given apps right away on all their devices, regardless of schedule or power source.
    func renew(_ ids: [ManagedApp.ID]) {
        forced.formUnion(ids.filter { store.app($0) != nil })
        enqueue(ids)
    }

    func renewAll() {
        renew(store.apps.filter(\.isEnabled).map(\.id))
    }

    func cancelAll() {
        for id in queue { store.activity[id] = .idle }
        queue.removeAll()
        forced.removeAll()
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
            if updateSavedDevices() { await checkDueApps() }
        } catch is CancellationError {
            // The view that asked for the refresh went away.
        } catch {
            store.record(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Scheduling

    /// Whether the app is due on at least one of its devices.
    func isDue(_ app: ManagedApp, now: Date = .now) -> Bool {
        app.isEnabled && store.targets(for: app).contains { isDue(app.installation(on: $0.id), now: now) }
    }

    func isDue(_ installation: Installation, now: Date = .now) -> Bool {
        // Looking for a device that was away is cheap, so only real failures wait.
        if installation.lastError != nil, !installation.isWaitingForDevice,
           let attempt = installation.lastAttempt, now.timeIntervalSince(attempt) < Self.retryInterval {
            return false
        }
        guard let installed = installation.lastInstall else { return true }
        if isUrgent(installation, now: now) { return true }
        return now.timeIntervalSince(installed) >= Double(store.preferences.renewAfterDays) * 86_400
    }

    private func isUrgent(_ installation: Installation, now: Date) -> Bool {
        guard let expiration = installation.expirationDate else { return false }
        return expiration.timeIntervalSince(now) < Self.urgentInterval
    }

    /// The devices a scheduled check renews the app on. On battery, only those where it
    /// expires within a day.
    func dueDevices(for app: ManagedApp, now: Date = .now) -> [SavedDevice] {
        guard app.isEnabled else { return [] }
        let onBattery = store.preferences.onlyOnPower && !PowerState.isOnExternalPower
        return store.targets(for: app).filter { device in
            let installation = app.installation(on: device.id)
            return isDue(installation, now: now) && (!onBattery || isUrgent(installation, now: now))
        }
    }

    func checkDueApps() async {
        let now = Date.now
        warnAboutExpiringApps(now: now)

        let due = store.apps.filter { !dueDevices(for: $0, now: now).isEmpty && !store.activity(for: $0).isBusy }
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
                forced.remove(id)
                store.activity[id] = .idle
            }
            worker = nil
            // cancelAll() empties the queue, so anything in it now was added afterwards.
            startWorkerIfNeeded()
        }
    }

    // MARK: - Renewal

    /// Builds the app once and installs it on every device it is due on. A device that is
    /// away or locked does not hold up the others.
    private func renewOne(_ id: ManagedApp.ID) async {
        guard let app = store.app(id) else { return }
        let isForced = forced.contains(id)
        defer {
            // Builds are only needed until the app is on the device. Keeping them would
            // duplicate Xcode's own build folder, a few hundred MB per app.
            BuildService.removeBuildFiles(for: app)
        }
        store.activity[id] = .preparing
        var problems: [String] = []
        var ready: [Device] = []

        do {
            let toolchain = try Toolchain.resolve(override: store.preferences.xcodePath)
            let deviceService = DeviceService(toolchain: toolchain)
            store.devices = (try? await deviceService.devices()) ?? []
            store.lastDeviceRefresh = .now
            updateSavedDevices()

            let targets = isForced ? store.targets(for: app) : dueDevices(for: app)
            guard !targets.isEmpty else {
                if store.targets(for: app).isEmpty {
                    let error = store.preferences.devices.isEmpty ? RenewError.noDeviceSelected : RenewError.noDeviceForApp
                    store.record(error.localizedDescription, app: app.name, isError: true)
                }
                return
            }

            for target in targets {
                do {
                    guard let device = store.liveDevice(target.id)?.named(target.name), device.isReachable else {
                        throw RenewError.deviceUnreachable(target.name)
                    }
                    try await deviceService.prepare(device)
                    ready.append(device)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    fail(app, on: target, error, problems: &problems)
                }
            }
            guard !ready.isEmpty else { return }

            store.record(String(localized: "Building for \(ready.map(\.name).formatted(.list(type: .and).locale(.interface)))…"), app: app.name)
            store.update(id) { app in
                for device in ready { app.installations[device.id, default: Installation()].lastAttempt = .now }
            }
            store.activity[id] = .building

            let buildLog = BuildLog(url: AppStore.buildLogURL(for: app))
            defer { buildLog.close() }
            let buildService = BuildService(toolchain: toolchain)
            let product = try await buildService.build(app) { buildLog.write($0) }
            let profile = ProfileInspector.embeddedProfile(inApp: product)
            IconLocator.cacheIcon(for: app, builtApp: product)

            // A device that is new to the Personal Team is not in the profile yet. Install on
            // the others first, so a failed registration cannot affect them.
            let unregistered = ready.filter { profile?.includes($0) == false }
            for device in ready where !unregistered.contains(device) {
                try await install(app, at: product, profile: profile, on: device, service: deviceService, log: buildLog, problems: &problems)
            }
            for device in unregistered {
                let saved = SavedDevice(device)
                do {
                    store.record(String(localized: "Adding \(device.name) to the provisioning profile…"), app: app.name)
                    store.activity[id] = .building
                    let product = try await buildService.build(app, registering: device) { buildLog.write($0) }
                    let profile = ProfileInspector.embeddedProfile(inApp: product)
                    guard profile?.includes(device) != false else { throw DeviceError.notRegistered(device.name) }
                    try await install(app, at: product, profile: profile, on: device, service: deviceService, log: buildLog, problems: &problems)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    fail(app, on: saved, error, problems: &problems)
                }
            }
        } catch is CancellationError {
            store.record(String(localized: "Cancelled."), app: app.name)
        } catch {
            // Xcode is missing or the build failed, which affects every device alike.
            let devices = ready.isEmpty ? store.targets(for: app) : ready.map(SavedDevice.init)
            failBuild(app, on: devices, error, problems: &problems)
        }

        // Devices that are away or locked are normal and covered by the expiry warning;
        // only new, real failures deserve a notification.
        if !problems.isEmpty {
            Notifier.post(
                title: String(localized: "\(app.name) could not be renewed"),
                body: problems.joined(separator: "\n"),
                kind: .failure,
                app: id
            )
        }
    }

    private func install(
        _ app: ManagedApp, at product: URL, profile: ProvisioningProfile?, on device: Device,
        service: DeviceService, log: BuildLog, problems: inout [String]
    ) async throws {
        store.activity[app.id] = .installing(on: device.name)
        do {
            try await service.install(appAt: product, on: device) { log.write($0) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            fail(app, on: SavedDevice(device), error, problems: &problems)
            return
        }
        store.update(app.id) { app in
            var installation = app.installation(on: device.id)
            installation.lastInstall = .now
            installation.expirationDate = profile?.expirationDate
            installation.lastError = nil
            installation.isWaitingForDevice = false
            app.installations[device.id] = installation
        }
        let until = profile?.expirationDate.formatted(date: .abbreviated, time: .shortened) ?? "–"
        store.record(String(localized: "Installed on \(device.name). Valid until \(until)."), app: app.name)
    }

    /// Records a problem with one device.
    private func fail(_ app: ManagedApp, on device: SavedDevice, _ error: Error, problems: inout [String]) {
        let message = message(for: error, on: device, of: app)
        markProblem(message, for: app, on: [device], isWaiting: (error as? RenewError)?.isWaitingForDevice ?? false,
                    reported: message, problems: &problems)
    }

    /// Records a problem that affects every device the app was being built for. The log and
    /// the notification mention it once.
    private func failBuild(_ app: ManagedApp, on devices: [SavedDevice], _ error: Error, problems: inout [String]) {
        let current = store.app(app.id) ?? app
        let isNewProblem = devices.contains { current.installation(on: $0.id).lastError != message(for: error, on: $0, of: app) }
        for device in devices {
            markProblem(message(for: error, on: device, of: app), for: app, on: [device], isWaiting: false,
                        reported: nil, problems: &problems)
        }
        store.record(error.localizedDescription, app: app.name, isError: true)
        if isNewProblem { problems.append(error.localizedDescription) }
    }

    /// With several devices, a message names the device it is about. Messages about a device
    /// that is away, locked or not registered name it already.
    private func message(for error: Error, on device: SavedDevice, of app: ManagedApp) -> String {
        let namesDevice = switch error {
        case RenewError.deviceUnreachable, RenewError.deviceLocked, DeviceError.notRegistered: true
        default: false
        }
        guard store.targets(for: app).count > 1, !namesDevice else { return error.localizedDescription }
        return String(localized: "\(device.name): \(error.localizedDescription)")
    }

    /// Saves the problem on the device. `reported` is logged, and becomes part of the
    /// notification if it is new and not just a device that is away.
    private func markProblem(
        _ message: String, for app: ManagedApp, on devices: [SavedDevice], isWaiting: Bool,
        reported: String?, problems: inout [String]
    ) {
        let current = store.app(app.id) ?? app
        let isNewProblem = devices.contains { current.installation(on: $0.id).lastError != message }
        store.update(app.id) { app in
            for device in devices {
                app.installations[device.id, default: Installation()].lastError = message
                app.installations[device.id, default: Installation()].isWaitingForDevice = isWaiting
            }
        }
        guard let reported else { return }
        store.record(reported, app: app.name, isError: true)
        if isNewProblem && !isWaiting { problems.append(reported) }
    }

    /// Keeps the names of chosen devices current, and chooses the only paired device when
    /// none is chosen yet. Returns whether a device was chosen.
    @discardableResult
    private func updateSavedDevices() -> Bool {
        for index in store.preferences.devices.indices {
            guard let live = store.liveDevice(store.preferences.devices[index].id) else { continue }
            let saved = SavedDevice(live)
            if store.preferences.devices[index] != saved { store.preferences.devices[index] = saved }
        }
        guard store.preferences.devices.isEmpty, store.devices.count == 1, let only = store.devices.first else { return false }
        store.preferences.devices = [SavedDevice(only)]
        return true
    }

    private func warnAboutExpiringApps(now: Date) {
        for app in store.apps where app.isEnabled {
            let targets = store.targets(for: app)
            for device in targets {
                let installation = app.installation(on: device.id)
                guard let expiration = installation.expirationDate,
                      isUrgent(installation, now: now),
                      expiration > now,
                      installation.warnedExpiration != expiration
                else { continue }
                store.update(app.id) { $0.installations[device.id]?.warnedExpiration = expiration }
                Notifier.post(
                    title: targets.count > 1
                        ? String(localized: "\(app.name) expires soon on \(device.name)")
                        : String(localized: "\(app.name) expires soon"),
                    body: String(localized: "Connect \(device.name) to the same Wi‑Fi as this Mac so KeepAlive can renew it."),
                    kind: .expiry,
                    app: app.id
                )
            }
        }
    }
}

extension SavedDevice {
    init(_ device: Device) {
        self.init(id: device.id, name: device.name, model: device.model, isPad: device.isPad)
    }
}

enum RenewError: LocalizedError {
    case noDeviceSelected
    case noDeviceForApp
    case deviceUnreachable(String)
    case deviceLocked(String)

    /// The device is fine but cannot be used right now, so KeepAlive keeps looking for it.
    var isWaitingForDevice: Bool {
        switch self {
        case .noDeviceSelected, .noDeviceForApp: false
        case .deviceUnreachable, .deviceLocked: true
        }
    }

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return String(localized: "No device selected. Choose one in Settings → Devices.")
        case .noDeviceForApp:
            return String(localized: "This app is turned off on every device. Turn on a device in its details under Apps.")
        case .deviceUnreachable(let name):
            return String(localized: "\(name) is not reachable. KeepAlive will try again later.")
        case .deviceLocked(let name):
            return String(localized: "Unlock \(name) once so KeepAlive can install apps. It will try again later.")
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
