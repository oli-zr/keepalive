import AppKit
import CryptoKit
import Observation

/// A release published on GitHub that is newer than the running app.
struct UpdateRelease: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
    let archiveURL: URL
    let checksumURL: URL
}

/// Dotted version numbers compared numerically, so 1.0.10 is newer than 1.0.9.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]
    let description: String

    init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
        description = trimmed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion("0")!
    }
}

enum UpdateError: LocalizedError {
    case unavailable
    case missingAsset
    case untrustedHost
    case checksumMismatch
    case invalidApp

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Could not reach GitHub to check for updates.")
        case .missingAsset: String(localized: "The release does not contain KeepAlive.zip.")
        case .untrustedHost: String(localized: "The update was not downloaded from GitHub and was discarded.")
        case .checksumMismatch: String(localized: "The downloaded update is damaged and was discarded.")
        case .invalidApp: String(localized: "The downloaded update is not a valid version of KeepAlive and was discarded.")
        }
    }
}

/// Checks GitHub once a day for a newer release, downloads and verifies it, and replaces
/// the app when no renewal is running.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading(UpdateRelease)
        case installing(UpdateRelease)
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var installTask: Task<Void, Never>?

    private static let previousVersionKey = "UpdatedFromVersion"

    init(store: AppStore) {
        self.store = store
    }

    var repository: String {
        Bundle.main.object(forInfoDictionaryKey: "KeepAliveUpdateRepository") as? String ?? "oli-zr/keepalive"
    }

    var availableRelease: UpdateRelease? {
        switch state {
        case .available(let release), .downloading(let release), .installing(let release): release
        default: nil
        }
    }

    /// Updates are only installed in place when KeepAlive lives in an Applications folder
    /// that can be written to. A build run from a project folder is left alone.
    var canInstallInPlace: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return [ "/Applications", userApplications ].contains(folder)
            && FileManager.default.isWritableFile(atPath: folder)
    }

    func start() {
        reportCompletedUpdate()
        removeStagedFiles()

        let scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "KeepAlive").update")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 6 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.checkAutomatically()
                completion(.finished)
            }
        }
        self.scheduler = scheduler

        Task {
            try? await Task.sleep(for: .seconds(60))
            let last = store.preferences.lastUpdateCheck ?? .distantPast
            if Date.now.timeIntervalSince(last) > 20 * 60 * 60 { await checkAutomatically() }
        }
    }

    // MARK: - Checking

    func checkNow() async {
        await check(installAutomatically: store.preferences.installsUpdates)
    }

    private func checkAutomatically() async {
        guard store.preferences.checksForUpdates else { return }
        await check(installAutomatically: store.preferences.installsUpdates)
    }

    private func check(installAutomatically: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        do {
            let release = try await latestRelease()
            store.preferences.lastUpdateCheck = .now
            guard let release, release.version > .current else {
                state = .upToDate
                return
            }
            state = .available(release)
            store.record(String(localized: "KeepAlive \(release.version.description) is available."))
            if installAutomatically && canInstallInPlace { install(release) }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func latestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { throw UpdateError.unavailable }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw UpdateError.unavailable }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !payload.draft, !payload.prerelease, let version = AppVersion(payload.tag_name) else { return nil }
        guard let archive = payload.assets.first(where: { $0.name == "KeepAlive.zip" }),
              let checksum = payload.assets.first(where: { $0.name == "KeepAlive.zip.sha256" })
        else { throw UpdateError.missingAsset }
        return UpdateRelease(version: version, pageURL: payload.html_url,
                             archiveURL: archive.browser_download_url, checksumURL: checksum.browser_download_url)
    }

    // MARK: - Installing

    /// Downloads and verifies the release, then installs it as soon as no renewal is running.
    /// Without write access to the app's folder it opens the release page instead.
    func install(_ release: UpdateRelease) {
        guard canInstallInPlace else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        guard installTask == nil else { return }
        installTask = Task {
            defer { installTask = nil }
            do {
                state = .downloading(release)
                let app = try await downloadAndVerify(release)
                while store.isBusy {
                    try await Task.sleep(for: .seconds(30))
                }
                state = .installing(release)
                try replaceAndRelaunch(with: app)
            } catch is CancellationError {
                state = .available(release)
            } catch {
                state = .failed(error.localizedDescription)
                store.record(error.localizedDescription, isError: true)
                removeStagedFiles()
            }
        }
    }

    private var stagingDirectory: URL {
        BuildService.supportDirectory.appendingPathComponent("Update", isDirectory: true)
    }

    private func downloadAndVerify(_ release: UpdateRelease) async throws -> URL {
        let fileManager = FileManager.default
        removeStagedFiles()
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let checksumFile = try await download(release.checksumURL)
        let expected = (try String(contentsOf: checksumFile, encoding: .utf8))
            .split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        let archive = try await download(release.archiveURL)
        let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        guard let expected, expected == actual else { throw UpdateError.checksumMismatch }

        let unpacked = stagingDirectory.appendingPathComponent("Unpacked", isDirectory: true)
        let unzip = try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path], timeout: 120)
        guard unzip.succeeded else { throw UpdateError.invalidApp }

        let app = unpacked.appendingPathComponent("KeepAlive.app")
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let version = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version > .current
        else { throw UpdateError.invalidApp }

        let signature = try await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120)
        guard signature.succeeded else { throw UpdateError.invalidApp }
        return app
    }

    private func download(_ url: URL) async throws -> URL {
        guard let (file, response) = try? await URLSession.shared.download(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { throw UpdateError.unavailable }
        // GitHub redirects release assets to its download servers.
        let host = http.url?.host() ?? ""
        guard http.url?.scheme == "https", host == "github.com" || host.hasSuffix(".githubusercontent.com") else {
            throw UpdateError.untrustedHost
        }
        let destination = stagingDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    /// Hands over to a small script that waits for KeepAlive to quit, swaps the app bundle
    /// and opens the new version. If the swap fails, the old app is put back.
    private func replaceAndRelaunch(with newApp: URL) throws {
        let destination = Bundle.main.bundleURL.path
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.5; done
            rm -rf "$3.new" "$3.old"
            if ditto "$2" "$3.new" && mv "$3" "$3.old" && mv "$3.new" "$3"; then
                rm -rf "$3.old"
            else
                [ -d "$3" ] || mv "$3.old" "$3"
                rm -rf "$3.new"
            fi
            rm -rf "$4"
            open "$3"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "keepalive-update",
                             String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination,
                             stagingDirectory.path]
        try process.run()

        UserDefaults.standard.set(AppVersion.current.description, forKey: Self.previousVersionKey)
        NSApp.terminate(nil)
    }

    private func reportCompletedUpdate() {
        guard let previous = UserDefaults.standard.string(forKey: Self.previousVersionKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.previousVersionKey)
        let current = AppVersion.current.description
        guard previous != current else { return }
        store.record(String(localized: "Updated from \(previous) to \(current)."))
        Notifier.post(
            title: String(localized: "KeepAlive was updated to \(current)"),
            body: String(localized: "Your apps and settings are unchanged.")
        )
    }

    private func removeStagedFiles() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}

// MARK: - GitHub API

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}
