import Foundation
import Testing
@testable import KeepAlive

@Suite("Versions")
struct VersionTests {
    func version(_ string: String) -> AppVersion { AppVersion(string)! }

    @Test("Compares numerically, not alphabetically")
    func numericComparison() {
        #expect(version("1.0.9") < version("1.0.10"))
        #expect(version("1.0.2") < version("1.1"))
        #expect(version("2.0") > version("1.99"))
    }

    @Test("Missing components count as zero")
    func trailingZeros() {
        #expect(version("1.1") == version("1.1.0"))
        #expect(!(version("1.0") < version("1.0")))
    }

    @Test("Accepts tags with a leading v")
    func leadingV() {
        #expect(version("v1.2") == version("1.2"))
        #expect(version("v1.2").description == "1.2")
    }

    @Test("Rejects anything that is not a version", arguments: ["", "v", "1.x", "beta", "1..2"])
    func invalid(_ string: String) {
        #expect(AppVersion(string) == nil)
    }
}

@Suite("GitHub releases")
struct ReleaseParsingTests {
    func payload(tag: String = "v1.2", draft: Bool = false, prerelease: Bool = false,
                 assets: [String] = ["KeepAlive.zip", "KeepAlive.zip.sha256"]) -> Data {
        let assetJSON = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/oli-zr/keepalive/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        return Data("""
            {"tag_name":"\(tag)","html_url":"https://github.com/oli-zr/keepalive/releases/tag/\(tag)",
             "draft":\(draft),"prerelease":\(prerelease),"assets":[\(assetJSON)]}
            """.utf8)
    }

    @Test("Reads version and asset links")
    func readsRelease() throws {
        let release = try #require(try Updater.release(from: payload()))
        #expect(release.version == AppVersion("1.2")!)
        #expect(release.archiveURL.lastPathComponent == "KeepAlive.zip")
        #expect(release.checksumURL.lastPathComponent == "KeepAlive.zip.sha256")
        #expect(release.pageURL.absoluteString.hasSuffix("/releases/tag/v1.2"))
    }

    @Test("Ignores drafts and prereleases")
    func ignoresUnfinishedReleases() throws {
        #expect(try Updater.release(from: payload(draft: true)) == nil)
        #expect(try Updater.release(from: payload(prerelease: true)) == nil)
    }

    @Test("Ignores tags that are not versions")
    func ignoresOtherTags() throws {
        #expect(try Updater.release(from: payload(tag: "nightly")) == nil)
    }

    @Test("Refuses a release without a checksum")
    func requiresChecksum() {
        #expect(throws: UpdateError.self) {
            try Updater.release(from: payload(assets: ["KeepAlive.zip"]))
        }
    }
}
