import Foundation

/// Turns raw `xcodebuild` and `devicectl` output into a sentence a person can act on.
enum Diagnostics {
    /// Output that means CoreDevice lost or never got a connection to the iPhone.
    private static let unreachableNeedles = [
        "unable to locate a device", "not connected", "Timed out while attempting to establish tunnel", "tunnel",
        "connection to this device could not be established", "CoreDeviceError error 4000",
    ]

    private static let hints: [(needles: [String], message: String.LocalizationValue)] = [
        (["No Accounts", "No Account for Team", "not signed in"],
         "Sign in to your Apple Account in Xcode → Settings → Accounts."),
        (["maximum number of apps", "maximum App ID limit"],
         "Apple’s limit for free accounts was reached. Remove an app from your iPhone or wait a few days."),
        (["Developer Mode"],
         "Turn on Developer Mode on your iPhone in Settings → Privacy & Security."),
        // The developer disk image (CoreDeviceError 12040) can only be mounted while the iPhone is unlocked.
        (["device is locked", "device is currently locked", "device was still locked", "passcode", "CoreDeviceError error 10003"],
         "Unlock your iPhone and try again."),
        (unreachableNeedles,
         "Your iPhone could not be reached. Make sure it is on the same Wi‑Fi network as this Mac."),
        (["requires a provisioning profile", "No profiles for"],
         "No provisioning profile could be created. Open the project in Xcode once and select your Personal Team under Signing & Capabilities."),
    ]

    static func explain(_ output: String) -> String {
        for hint in hints where hint.needles.contains(where: { output.localizedCaseInsensitiveContains($0) }) {
            return String(localized: hint.message)
        }
        return firstError(in: output) ?? output.lastMeaningfulLine
    }

    /// Whether the device went away, which is worth retrying when it is back rather than reporting.
    static func isUnreachable(_ output: String) -> Bool {
        unreachableNeedles.contains { output.localizedCaseInsensitiveContains($0) }
    }

    static func firstError(in output: String) -> String? {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("error:") || $0.contains(": error:") || $0.hasPrefix("ERROR:") }
            .map { line in
                guard let range = line.range(of: "error:", options: .caseInsensitive) else { return line }
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
    }
}
