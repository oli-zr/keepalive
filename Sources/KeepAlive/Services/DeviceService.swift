import Foundation

struct Device: Identifiable, Hashable, Codable, Sendable {
    /// CoreDevice identifier, accepted by `devicectl --device`.
    let id: String
    /// Hardware identifier, as listed in provisioning profiles.
    let udid: String?
    let name: String
    let model: String
    let isPad: Bool
    let transport: Transport
    let isReachable: Bool

    enum Transport: String, Codable, Sendable {
        case wired, network, unknown
    }

    /// The same device under the name KeepAlive shows for it.
    func named(_ name: String) -> Device {
        Device(id: id, udid: udid, name: name, model: model, isPad: isPad, transport: transport, isReachable: isReachable)
    }
}

enum DeviceError: LocalizedError {
    case listFailed(String)
    case installFailed(String)
    case notRegistered(String)

    var errorDescription: String? {
        switch self {
        case .listFailed(let detail):
            return String(localized: "Could not list devices: \(detail)")
        case .installFailed(let detail):
            return String(localized: "Installation failed: \(detail)")
        case .notRegistered(let name):
            return String(localized: "\(name) could not be added to the provisioning profile. Open the project in Xcode and run it on \(name) once.")
        }
    }
}

/// Talks to physical iPhones and iPads through `devicectl`.
struct DeviceService: Sendable {
    let toolchain: Toolchain

    func devices() async throws -> [Device] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("keepalive-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await Shell.run(
            Toolchain.xcrun,
            ["devicectl", "list", "devices", "--quiet", "--json-output", output.path],
            environment: toolchain.environment,
            timeout: 60
        )
        guard let data = try? Data(contentsOf: output) else {
            throw DeviceError.listFailed(result.output.lastMeaningfulLine)
        }
        return try Self.parseDevices(data)
    }

    /// Paired physical iPhones and iPads from `devicectl list devices --json-output`.
    static func parseDevices(_ data: Data) throws -> [Device] {
        try JSONDecoder().decode(ListResponse.self, from: data).result.devices.compactMap(\.device)
    }

    /// Mounts the developer disk image, which iOS only allows while the iPhone is unlocked.
    /// Checking before the build avoids building an app that cannot be installed yet.
    /// Other failures are left to the installation, which explains them.
    func prepare(_ device: Device) async throws {
        let result = try await Shell.run(
            Toolchain.xcrun,
            ["devicectl", "device", "info", "ddiServices", "--device", device.id],
            environment: toolchain.environment,
            timeout: 2 * 60
        )
        if !result.succeeded, Diagnostics.isLocked(result.output) { throw RenewError.deviceLocked(device.name) }
    }

    func install(appAt appURL: URL, on device: Device, onLine: (@Sendable (String) -> Void)? = nil) async throws {
        let result = try await Shell.run(
            Toolchain.xcrun,
            ["devicectl", "device", "install", "app", "--device", device.id, appURL.path],
            environment: toolchain.environment,
            timeout: 10 * 60,
            onLine: onLine
        )
        guard result.succeeded else {
            // The iPhone can lock or leave the Wi‑Fi while the app is being built.
            if Diagnostics.isUnreachable(result.output) { throw RenewError.deviceUnreachable(device.name) }
            if Diagnostics.isLocked(result.output) { throw RenewError.deviceLocked(device.name) }
            throw DeviceError.installFailed(Diagnostics.explain(result.output))
        }
    }
}

// MARK: - devicectl JSON

private struct ListResponse: Decodable {
    struct Result: Decodable { let devices: [RawDevice] }
    let result: Result
}

private struct RawDevice: Decodable {
    struct Connection: Decodable {
        let pairingState: String?
        let transportType: String?
        let tunnelState: String?
    }
    struct Properties: Decodable {
        let name: String?
    }
    struct Hardware: Decodable {
        let reality: String?
        let platform: String?
        let marketingName: String?
        let deviceType: String?
        let udid: String?
    }

    let identifier: String
    let connectionProperties: Connection?
    let deviceProperties: Properties?
    let hardwareProperties: Hardware?

    var device: Device? {
        // Xcode 27 omits `reality` for physical devices, so simulators are also
        // recognized by their `sameMachine` transport.
        guard let hardware = hardwareProperties,
              hardware.reality != "simulated",
              connectionProperties?.transportType != "sameMachine",
              hardware.platform == "iOS",
              connectionProperties?.pairingState == "paired"
        else { return nil }

        let transport: Device.Transport
        switch connectionProperties?.transportType {
        case "wired": transport = .wired
        case "localNetwork": transport = .network
        default: transport = .unknown
        }
        // "unavailable" means CoreDevice cannot see the device at all right now.
        let tunnel = connectionProperties?.tunnelState ?? "unavailable"
        let reachable = tunnel != "unavailable" && transport != .unknown

        let model = hardware.marketingName ?? ""
        return Device(
            id: identifier,
            udid: hardware.udid,
            name: deviceProperties?.name ?? hardware.marketingName ?? "iPhone",
            model: model,
            isPad: hardware.deviceType.map { $0 == "iPad" } ?? model.hasPrefix("iPad"),
            transport: transport,
            isReachable: reachable
        )
    }
}

extension String {
    var lastMeaningfulLine: String {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }
}
