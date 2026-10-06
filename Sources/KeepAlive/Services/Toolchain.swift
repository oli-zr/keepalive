import Foundation

enum ToolchainError: LocalizedError {
    case xcodeNotFound

    var errorDescription: String? {
        String(localized: "Xcode was not found. Install Xcode or choose its location in Settings.")
    }
}

/// Locates the full Xcode installation. `xcode-select` often points at the Command Line
/// Tools, which lack `xcodebuild` and `devicectl`, so we look for Xcode ourselves.
struct Toolchain: Sendable {
    let developerDirectory: String

    static let xcrun = "/usr/bin/xcrun"

    var environment: [String: String] { ["DEVELOPER_DIR": developerDirectory] }

    var xcodeAppPath: String {
        URL(fileURLWithPath: developerDirectory).deletingLastPathComponent().deletingLastPathComponent().path
    }

    static func resolve(override: String?) throws -> Toolchain {
        if let override, let directory = developerDirectory(forXcodeAt: override) {
            return Toolchain(developerDirectory: directory)
        }
        if let selected = selectedDeveloperDirectory(), selected.contains(".app/Contents/Developer") {
            return Toolchain(developerDirectory: selected)
        }
        if let directory = installedXcodes().lazy.compactMap(developerDirectory(forXcodeAt:)).first {
            return Toolchain(developerDirectory: directory)
        }
        throw ToolchainError.xcodeNotFound
    }

    /// Accepts either `Xcode.app` or its `Contents/Developer` folder.
    static func developerDirectory(forXcodeAt path: String) -> String? {
        let candidates = [path, path + "/Contents/Developer"]
        return candidates.first { FileManager.default.fileExists(atPath: $0 + "/usr/bin/xcodebuild") }
    }

    static func installedXcodes() -> [String] {
        let applications = "/Applications"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: applications)) ?? []
        return names
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted { lhs, rhs in
                // Prefer the plain "Xcode.app" over betas and renamed copies.
                if lhs == "Xcode.app" { return true }
                if rhs == "Xcode.app" { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedDescending
            }
            .map { "\(applications)/\($0)" }
    }

    /// What `xcode-select -p` prints. It only reads this link, so we read it directly instead
    /// of starting a process, which is unsafe while SwiftUI is drawing.
    private static func selectedDeveloperDirectory() -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
    }
}
