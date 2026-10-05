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
        if !ephemeral { load() }
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
            try? FileManager.default.removeItem(at: BuildService.supportDirectory
                .appendingPathComponent("DerivedData/\(app.id.uuidString)"))
        }
        apps.removeAll { $0.id == id }
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
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logFileURL)
        }
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
