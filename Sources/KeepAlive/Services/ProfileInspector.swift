import Foundation
import Security

struct ProvisioningProfile: Sendable {
    let url: URL
    let name: String
    /// Team prefix plus bundle identifier, for example `ABCDE12345.com.example.app`.
    let applicationIdentifier: String
    let expirationDate: Date

    func matches(bundleIdentifier: String) -> Bool {
        guard let dot = applicationIdentifier.firstIndex(of: ".") else { return false }
        return applicationIdentifier[applicationIdentifier.index(after: dot)...] == bundleIdentifier
    }
}

/// Reads provisioning profiles and clears Xcode's cached copies, so the next build
/// receives a fresh seven-day profile instead of reusing one that is half expired.
enum ProfileInspector {
    static let cacheDirectories: [URL] = {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return [
            library.appendingPathComponent("Developer/Xcode/UserData/Provisioning Profiles"),
            library.appendingPathComponent("MobileDevice/Provisioning Profiles"),
        ]
    }()

    static func profile(at url: URL) -> ProvisioningProfile? {
        guard let data = try? Data(contentsOf: url),
              let plist = decode(data),
              let expiration = plist["ExpirationDate"] as? Date,
              let entitlements = plist["Entitlements"] as? [String: Any],
              let identifier = entitlements["application-identifier"] as? String
        else { return nil }
        return ProvisioningProfile(
            url: url,
            name: plist["Name"] as? String ?? url.lastPathComponent,
            applicationIdentifier: identifier,
            expirationDate: expiration
        )
    }

    static func embeddedProfile(inApp appURL: URL) -> ProvisioningProfile? {
        profile(at: appURL.appendingPathComponent("embedded.mobileprovision"))
    }

    /// Removes cached profiles for exactly this bundle identifier. Wildcard and
    /// other apps' profiles are left alone.
    @discardableResult
    static func removeCachedProfiles(for bundleIdentifier: String) -> Int {
        var removed = 0
        for directory in cacheDirectories {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where ["mobileprovision", "provisionprofile"].contains(file.pathExtension) {
                guard let profile = profile(at: file), profile.matches(bundleIdentifier: bundleIdentifier) else { continue }
                if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
            }
        }
        return removed
    }

    private static func decode(_ data: Data) -> [String: Any]? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        let status = data.withUnsafeBytes { buffer in
            CMSDecoderUpdateMessage(decoder, buffer.baseAddress!, buffer.count)
        }
        guard status == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }

        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else { return nil }
        return try? PropertyListSerialization.propertyList(from: content as Data, format: nil) as? [String: Any]
    }
}
