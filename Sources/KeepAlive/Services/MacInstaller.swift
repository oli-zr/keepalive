import AppKit
import CoreServices
import SystemConfiguration

enum MacInstallError: LocalizedError {
    case occupied(String)

    var errorDescription: String? {
        switch self {
        case .occupied(let path):
            return String(localized: "There is already a different app at \(path). Rename or remove it, so KeepAlive can install this app on this Mac.")
        }
    }
}

/// Installs iPhone and iPad apps on this Mac, where Apple silicon runs them as
/// “Designed for iPad” apps. The build is the same one that goes to the devices; the Mac
/// only has to be in its provisioning profile.
///
/// KeepAlive puts the app into `~/Applications`, in the same wrapper Xcode uses:
///
///     App.app/
///       Wrapper/App.app        the signed build
///       WrappedBundle -> Wrapper/App.app
///
/// The app’s data lives in its container under `~/Library/Containers`, so it survives
/// a reinstall.
enum MacInstaller {
    static let applicationsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)

    /// This Mac as a device, or `nil` on an Intel Mac, which cannot run iPhone and iPad apps.
    static func thisMac() async -> Device? {
        guard isAppleSilicon,
              let result = try? await Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], timeout: 60),
              result.succeeded,
              let hardware = parseHardware(Data(result.output.utf8))
        else { return nil }
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String?
        return Device(
            id: hardware.udid,
            udid: hardware.udid,
            name: computerName.flatMap { $0.isEmpty ? nil : $0 } ?? hardware.model,
            model: hardware.model,
            isPad: false,
            transport: .local,
            isReachable: true,
            isMac: true
        )
    }

    /// The provisioning UDID, which provisioning profiles list for a Mac, and the model name
    /// from `system_profiler SPHardwareDataType -json`.
    static func parseHardware(_ data: Data) -> (udid: String, model: String)? {
        struct Response: Decodable {
            struct Hardware: Decodable {
                let provisioning_UDID: String?
                let machine_name: String?
            }
            let SPHardwareDataType: [Hardware]
        }
        guard let hardware = (try? JSONDecoder().decode(Response.self, from: data))?.SPHardwareDataType.first,
              let udid = hardware.provisioning_UDID, !udid.isEmpty
        else { return nil }
        return (udid, hardware.machine_name ?? "Mac")
    }

    /// Also true when KeepAlive itself runs under Rosetta.
    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    /// macOS runs the app straight from its wrapper, so replacing it while it is open
    /// would pull files away from under it.
    @MainActor
    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Puts the app into its wrapper, replacing an earlier version in one step, and returns
    /// the wrapper. A different app at the same place is left alone.
    @discardableResult
    static func install(
        appAt product: URL, bundleIdentifier: String,
        into applications: URL = applicationsDirectory, registers: Bool = true
    ) throws -> URL {
        let fileManager = FileManager.default
        let name = product.lastPathComponent
        let wrapper = applications.appendingPathComponent(name, isDirectory: true)
        let installed = wrapper.appendingPathComponent("Wrapper/\(name)", isDirectory: true)
        let link = wrapper.appendingPathComponent("WrappedBundle")

        let exists = fileManager.fileExists(atPath: wrapper.path)
        if exists, Self.bundleIdentifier(of: installed) != bundleIdentifier {
            throw MacInstallError.occupied(wrapper.path.replacingOccurrences(of: fileManager.homeDirectoryForCurrentUser.path, with: "~"))
        }

        try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: applications, create: true)
        defer { try? fileManager.removeItem(at: staging) }

        if exists {
            let copy = staging.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: product, to: copy)
            _ = try fileManager.replaceItemAt(installed, withItemAt: copy)
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != "Wrapper/\(name)" {
                try? fileManager.removeItem(at: link)
                try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "Wrapper/\(name)")
            }
        } else {
            let staged = staging.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: staged.appendingPathComponent("Wrapper"), withIntermediateDirectories: true)
            try fileManager.copyItem(at: product, to: staged.appendingPathComponent("Wrapper/\(name)"))
            try fileManager.createSymbolicLink(
                atPath: staged.appendingPathComponent("WrappedBundle").path, withDestinationPath: "Wrapper/\(name)")
            try fileManager.moveItem(at: staged, to: wrapper)
        }

        // Launchpad and Spotlight pick up the new version without waiting for a rescan.
        if registers { LSRegisterURL(wrapper as CFURL, true) }
        return wrapper
    }

    static func bundleIdentifier(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }
}
