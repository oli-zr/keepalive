import Foundation

/// An Xcode project that KeepAlive builds and reinstalls on a schedule.
struct ManagedApp: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Path to an `.xcodeproj` or `.xcworkspace`.
    var projectPath: String
    var scheme: String
    var bundleIdentifier: String
    /// Product file name, for example `Hitster.app`.
    var productName: String
    /// Optional shell command run in the project folder before building,
    /// for example `flutter build ios --release --config-only`.
    var preBuildCommand: String = ""
    var isEnabled = true

    var lastInstall: Date?
    var expirationDate: Date?
    var lastAttempt: Date?
    var lastError: String?
    /// Expiration date we already sent a warning for, so we warn once per profile.
    var warnedExpiration: Date?

    var projectURL: URL { URL(fileURLWithPath: projectPath) }
    var isWorkspace: Bool { projectURL.pathExtension == "xcworkspace" }
    var projectDirectory: URL { projectURL.deletingLastPathComponent() }
}

struct Preferences: Codable, Sendable {
    var deviceIdentifier: String?
    var deviceName: String?
    var renewAfterDays = 3
    var onlyOnPower = true
    /// Path to a specific Xcode.app; `nil` picks one automatically.
    var xcodePath: String?
    var checksForUpdates = true
    var installsUpdates = true
    var lastUpdateCheck: Date?
}

/// Live state of a single app. Not persisted.
enum Activity: Equatable {
    case idle
    case waiting
    case preparing
    case building
    case installing

    var isBusy: Bool { self != .idle }
}

// Tolerate missing keys, so settings written by older versions keep loading.
extension ManagedApp {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        scheme = try c.decode(String.self, forKey: .scheme)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        productName = try c.decode(String.self, forKey: .productName)
        preBuildCommand = try c.decodeIfPresent(String.self, forKey: .preBuildCommand) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastInstall = try c.decodeIfPresent(Date.self, forKey: .lastInstall)
        expirationDate = try c.decodeIfPresent(Date.self, forKey: .expirationDate)
        lastAttempt = try c.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        warnedExpiration = try c.decodeIfPresent(Date.self, forKey: .warnedExpiration)
    }
}

extension Preferences {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceIdentifier = try c.decodeIfPresent(String.self, forKey: .deviceIdentifier)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        renewAfterDays = try c.decodeIfPresent(Int.self, forKey: .renewAfterDays) ?? 3
        onlyOnPower = try c.decodeIfPresent(Bool.self, forKey: .onlyOnPower) ?? true
        xcodePath = try c.decodeIfPresent(String.self, forKey: .xcodePath)
        checksForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? true
        installsUpdates = try c.decodeIfPresent(Bool.self, forKey: .installsUpdates) ?? true
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
    }
}
