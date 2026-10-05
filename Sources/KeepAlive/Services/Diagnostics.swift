import Foundation

/// Turns raw `xcodebuild` and `devicectl` output into a sentence a person can act on.
enum Diagnostics {
    private static let hints: [(needles: [String], message: String.LocalizationValue)] = [
        (["No Accounts", "No Account for Team", "not signed in"],
         "Sign in to your Apple Account in Xcode → Settings → Accounts."),
        (["maximum number of apps", "maximum App ID limit"],
         "Apple’s limit for free accounts was reached. Remove an app from your iPhone or wait a few days."),
        (["Developer Mode"],
         "Turn on Developer Mode on your iPhone in Settings → Privacy & Security."),
        (["device is locked", "passcode"],
         "Unlock your iPhone and try again."),
        (["unable to locate a device", "not connected", "Timed out while attempting to establish tunnel", "tunnel"],
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
