import Foundation
import Testing
@testable import KeepAlive

/// A temporary folder that is deleted when the test ends.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("KeepAliveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func make(_ path: String) throws -> URL {
        let item = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        return item
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@Suite("Finding projects")
struct ResolveProjectTests {
    @Test("Prefers the workspace next to a project")
    func workspaceWins() throws {
        let folder = try TemporaryFolder()
        let project = try folder.make("App.xcodeproj")
        try folder.make("App.xcworkspace")
        #expect(BuildService.resolveProject(at: project)?.lastPathComponent == "App.xcworkspace")
    }

    @Test("Keeps a project without a workspace")
    func projectAlone() throws {
        let folder = try TemporaryFolder()
        let project = try folder.make("App.xcodeproj")
        #expect(BuildService.resolveProject(at: project) == project)
    }

    @Test("Finds the project inside a chosen folder")
    func folder() throws {
        let folder = try TemporaryFolder()
        try folder.make("App.xcodeproj")
        #expect(BuildService.resolveProject(at: folder.url)?.lastPathComponent == "App.xcodeproj")
    }

    @Test("Looks into the ios folder of Flutter and React Native projects")
    func crossPlatform() throws {
        let folder = try TemporaryFolder()
        try folder.make("ios/Runner.xcodeproj")
        try folder.make("ios/Runner.xcworkspace")
        #expect(BuildService.resolveProject(at: folder.url)?.path.hasSuffix("ios/Runner.xcworkspace") == true)
    }

    @Test("Returns nothing for a folder without a project")
    func nothing() throws {
        let folder = try TemporaryFolder()
        try folder.make("Sources")
        #expect(BuildService.resolveProject(at: folder.url) == nil)
    }
}

@Suite("Finding Xcode")
struct ToolchainTests {
    @Test("Accepts Xcode.app and its Developer folder")
    func developerDirectory() throws {
        let folder = try TemporaryFolder()
        let developer = try folder.make("Xcode.app/Contents/Developer/usr/bin")
        FileManager.default.createFile(atPath: developer.appendingPathComponent("xcodebuild").path, contents: Data())
        let app = folder.url.appendingPathComponent("Xcode.app").path

        #expect(Toolchain.developerDirectory(forXcodeAt: app) == app + "/Contents/Developer")
        #expect(Toolchain.developerDirectory(forXcodeAt: app + "/Contents/Developer") == app + "/Contents/Developer")
    }

    @Test("Rejects folders that are not Xcode")
    func notXcode() throws {
        let folder = try TemporaryFolder()
        try folder.make("Other.app/Contents")
        #expect(Toolchain.developerDirectory(forXcodeAt: folder.url.appendingPathComponent("Other.app").path) == nil)
    }

    @Test("Derives the app path from the Developer folder")
    func appPath() {
        let toolchain = Toolchain(developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer")
        #expect(toolchain.xcodeAppPath == "/Applications/Xcode-beta.app")
        #expect(toolchain.environment == ["DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"])
    }
}

@Suite("Provisioning profiles")
struct ProfileTests {
    func profile(_ identifier: String) -> ProvisioningProfile {
        ProvisioningProfile(url: URL(fileURLWithPath: "/tmp/p.mobileprovision"), name: "Test",
                            applicationIdentifier: identifier, expirationDate: .now)
    }

    @Test("Matches the bundle identifier after the team prefix")
    func matches() {
        #expect(profile("ABCDE12345.com.example.App").matches(bundleIdentifier: "com.example.App"))
    }

    @Test("Does not match other apps, prefixes or wildcards", arguments: [
        "ABCDE12345.com.example.App2", "ABCDE12345.com.example", "ABCDE12345.*", "com.example.App",
    ])
    func noMatch(_ identifier: String) {
        #expect(!profile(identifier).matches(bundleIdentifier: "com.example.App"))
    }

    @Test("Ignores files that are not signed profiles")
    func unreadable() throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appendingPathComponent("broken.mobileprovision")
        try Data("not a profile".utf8).write(to: file)
        #expect(ProfileInspector.profile(at: file) == nil)
    }
}
