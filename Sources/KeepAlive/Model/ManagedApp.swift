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
    /// Devices this app is not installed on. Everything else KeepAlive uses gets it,
    /// so a newly chosen device receives all apps without editing each one.
    var excludedDevices: Set<Device.ID> = []
    /// What happened on each device, keyed by device ID.
    var installations: [Device.ID: Installation] = [:]

    var projectURL: URL { URL(fileURLWithPath: projectPath) }
    var isWorkspace: Bool { projectURL.pathExtension == "xcworkspace" }
    var projectDirectory: URL { projectURL.deletingLastPathComponent() }

    func installation(on device: Device.ID) -> Installation {
        installations[device] ?? Installation()
    }
}

/// The state of one app on one device.
struct Installation: Codable, Hashable, Sendable {
    var lastInstall: Date?
    var expirationDate: Date?
    var lastAttempt: Date?
    var lastError: String?
    /// The last attempt failed only because the device could not be found or was locked.
    var isWaitingForDevice = false
    /// Expiration date we already sent a warning for, so we warn once per profile.
    var warnedExpiration: Date?
}

/// A device chosen in Settings → Devices. The name is kept so it can be shown while
/// the device is away.
struct SavedDevice: Identifiable, Codable, Hashable, Sendable {
    let id: Device.ID
    var name: String
    var model = ""
    var isPad = false
}

struct Preferences: Codable, Sendable {
    /// The devices KeepAlive installs apps on.
    var devices: [SavedDevice] = []
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
    case installing(on: String)

    var isBusy: Bool { self != .idle }
}

// Tolerate missing keys, so settings written by older versions keep loading.
extension ManagedApp {
    private enum LegacyKeys: String, CodingKey {
        case lastInstall, expirationDate, lastAttempt, lastError, isWaitingForDevice, warnedExpiration
    }

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
        excludedDevices = try c.decodeIfPresent(Set<Device.ID>.self, forKey: .excludedDevices) ?? []
        if let installations = try c.decodeIfPresent([Device.ID: Installation].self, forKey: .installations) {
            self.installations = installations
        } else if let device = decoder.userInfo[.legacyDevice] as? Device.ID {
            // Up to 1.2, KeepAlive used one device and kept its state on the app.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let installation = Installation(
                lastInstall: try legacy.decodeIfPresent(Date.self, forKey: .lastInstall),
                expirationDate: try legacy.decodeIfPresent(Date.self, forKey: .expirationDate),
                lastAttempt: try legacy.decodeIfPresent(Date.self, forKey: .lastAttempt),
                lastError: try legacy.decodeIfPresent(String.self, forKey: .lastError),
                isWaitingForDevice: try legacy.decodeIfPresent(Bool.self, forKey: .isWaitingForDevice) ?? false,
                warnedExpiration: try legacy.decodeIfPresent(Date.self, forKey: .warnedExpiration)
            )
            if installation != Installation() { installations = [device: installation] }
        }
    }
}

extension Installation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastInstall = try c.decodeIfPresent(Date.self, forKey: .lastInstall)
        expirationDate = try c.decodeIfPresent(Date.self, forKey: .expirationDate)
        lastAttempt = try c.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        isWaitingForDevice = try c.decodeIfPresent(Bool.self, forKey: .isWaitingForDevice) ?? false
        warnedExpiration = try c.decodeIfPresent(Date.self, forKey: .warnedExpiration)
    }
}

extension SavedDevice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Device.ID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        isPad = try c.decodeIfPresent(Bool.self, forKey: .isPad) ?? false
    }
}

extension Preferences {
    private enum LegacyKeys: String, CodingKey {
        case deviceIdentifier, deviceName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let devices = try c.decodeIfPresent([SavedDevice].self, forKey: .devices) {
            self.devices = devices
        } else {
            // Up to 1.2, KeepAlive used one device.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let id = try legacy.decodeIfPresent(String.self, forKey: .deviceIdentifier) {
                let name = try legacy.decodeIfPresent(String.self, forKey: .deviceName) ?? "iPhone"
                devices = [SavedDevice(id: id, name: name)]
            }
        }
        renewAfterDays = try c.decodeIfPresent(Int.self, forKey: .renewAfterDays) ?? 3
        onlyOnPower = try c.decodeIfPresent(Bool.self, forKey: .onlyOnPower) ?? true
        xcodePath = try c.decodeIfPresent(String.self, forKey: .xcodePath)
        checksForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? true
        installsUpdates = try c.decodeIfPresent(Bool.self, forKey: .installsUpdates) ?? true
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
    }

    /// The device that versions up to 1.2 used, read before the apps so their state can move to it.
    static func legacyDevice(in settings: Data) -> Device.ID? {
        struct Stored: Decodable {
            struct Legacy: Decodable { let deviceIdentifier: String? }
            let preferences: Legacy
        }
        return (try? JSONDecoder().decode(Stored.self, from: settings))?.preferences.deviceIdentifier
    }
}

extension CodingUserInfoKey {
    /// The device that settings from versions up to 1.2 belong to.
    static let legacyDevice = CodingUserInfoKey(rawValue: "legacyDevice")!
}
