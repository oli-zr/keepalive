import Foundation

struct Device: Identifiable, Hashable, Codable, Sendable {
    /// CoreDevice identifier, accepted by `devicectl --device`.
    let id: String
    let udid: String
    let name: String
    let model: String
    let transport: Transport
    let isReachable: Bool

    enum Transport: String, Codable, Sendable {
        case wired, network, unknown
    }
}

enum DeviceError: LocalizedError {
    case listFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .listFailed(let detail):
            return String(localized: "Could not list devices: \(detail)")
        case .installFailed(let detail):
            return String(localized: "Installation failed: \(detail)")
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
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return response.result.devices.compactMap(\.device)
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
        let udid: String?
    }

    let identifier: String
    let connectionProperties: Connection?
    let deviceProperties: Properties?
    let hardwareProperties: Hardware?

    var device: Device? {
        guard let hardware = hardwareProperties,
              hardware.reality == "physical",
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

        return Device(
            id: identifier,
            udid: hardware.udid ?? identifier,
            name: deviceProperties?.name ?? hardware.marketingName ?? "iPhone",
            model: hardware.marketingName ?? "",
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
