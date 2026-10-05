import Foundation
import Observation

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let app: String?
    let message: String
    let isError: Bool
}

/// The single source of truth for settings, managed apps and live progress.
@MainActor
@Observable
final class AppStore {
    var apps: [ManagedApp] = [] {
        didSet { save() }
    }
    var preferences = Preferences() {
        didSet { save() }
    }

    /// Live progress per app. Not persisted.
    var activity: [ManagedApp.ID: Activity] = [:]
    var devices: [Device] = []
    var lastDeviceRefresh: Date?
    var log: [LogEntry] = []

    var isBusy: Bool { activity.values.contains { $0.isBusy } }

    var selectedDevice: Device? {
        devices.first { $0.id == preferences.deviceIdentifier }
    }

    var hasProblem: Bool {
        apps.contains { $0.isEnabled && $0.lastError != nil }
    }

    private let settingsURL = BuildService.supportDirectory.appendingPathComponent("Settings.json")
    static let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/KeepAlive", isDirectory: true)
    private var isLoading = false
    /// Debug previews use sample data that must never be written to disk.
    private let isEphemeral: Bool

    init(ephemeral: Bool = false) {
        isEphemeral = ephemeral
        if !ephemeral {
            load()
            removeOrphanedFiles()
        }
    }

    func activity(for app: ManagedApp) -> Activity {
        activity[app.id] ?? .idle
    }

    func update(_ id: ManagedApp.ID, _ change: (inout ManagedApp) -> Void) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        change(&apps[index])
    }

    func app(_ id: ManagedApp.ID) -> ManagedApp? {
        apps.first { $0.id == id }
    }

    func remove(_ id: ManagedApp.ID) {
        if let app = app(id) {
            IconLocator.removeIcon(for: app)
            BuildService.removeBuildFiles(for: app)
            try? FileManager.default.removeItem(at: Self.buildLogURL(for: app))
        }
        apps.removeAll { $0.id == id }
    }

    /// Deletes icons, build logs and build folders that belong to no app, for example
    /// after a crash or a rename.
    private func removeOrphanedFiles() {
        let fileManager = FileManager.default
        let ids = Set(apps.map(\.id.uuidString))
        let currentLogs = Set(apps.map { Self.buildLogURL(for: $0).lastPathComponent })

        func contents(_ url: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }
        for icon in contents(IconLocator.directory) where !ids.contains(icon.deletingPathExtension().lastPathComponent) {
            try? fileManager.removeItem(at: icon)
        }
        for folder in contents(BuildService.supportDirectory.appendingPathComponent("DerivedData")) {
            // A build folder is only kept while a renewal runs, so any leftover can go.
            try? fileManager.removeItem(at: folder)
        }
        for log in contents(Self.logDirectory)
        where log.lastPathComponent != logFileURL.lastPathComponent && !currentLogs.contains(log.lastPathComponent) {
            try? fileManager.removeItem(at: log)
        }
    }

    // MARK: - Log

    func record(_ message: String, app: String? = nil, isError: Bool = false) {
        let entry = LogEntry(date: .now, app: app, message: message, isError: isError)
        log.append(entry)
        if log.count > 500 { log.removeFirst(log.count - 500) }
        if !isEphemeral { appendToLogFile(entry) }
    }

    var logFileURL: URL { Self.logDirectory.appendingPathComponent("KeepAlive.log") }

    static func buildLogURL(for app: ManagedApp) -> URL {
        logDirectory.appendingPathComponent("\(app.name)-\(app.id.uuidString.prefix(8)).log")
    }

    private func appendToLogFile(_ entry: LogEntry) {
        let formatter = ISO8601DateFormatter()
        let prefix = entry.app.map { "[\($0)] " } ?? ""
        let line = "\(formatter.string(from: entry.date)) \(entry.isError ? "ERROR " : "")\(prefix)\(entry.message)\n"
        try? FileManager.default.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            let size = handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
            if size > Self.logSizeLimit { trimLogFile() }
        } else {
            try? Data(line.utf8).write(to: logFileURL)
        }
    }

    private static let logSizeLimit: UInt64 = 256 * 1024

    /// Keeps the newest half of the log so it never grows beyond a few hundred KB.
    private func trimLogFile() {
        guard let data = try? Data(contentsOf: logFileURL) else { return }
        var tail = data.suffix(Int(Self.logSizeLimit / 2))
        if let newline = tail.firstIndex(of: 0x0A) { tail = tail[tail.index(after: newline)...] }
        try? Data(tail).write(to: logFileURL, options: .atomic)
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var apps: [ManagedApp]
        var preferences: Preferences
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: settingsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data) else { return }
        apps = stored.apps
        preferences = stored.preferences
    }

    private func save() {
        guard !isLoading, !isEphemeral else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Stored(apps: apps, preferences: preferences)) else { return }
        try? FileManager.default.createDirectory(at: BuildService.supportDirectory, withIntermediateDirectories: true)
        try? data.write(to: settingsURL, options: .atomic)
    }
}
