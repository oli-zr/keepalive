import Foundation
import Testing
@testable import KeepAlive

@Suite("This Mac")
struct MacTests {
    @Test("Reads the provisioning UDID and model of this Mac")
    func hardware() throws {
        let json = Data("""
            {"SPHardwareDataType":[{"_name":"hardware_overview","chip_type":"Apple M3","machine_model":"Mac15,12",
              "machine_name":"MacBook Air","platform_UUID":"0A31343B-93C4-5E04-8BE7-171A08E2854A",
              "provisioning_UDID":"00008122-001C11102186001C"}]}
            """.utf8)
        let hardware = try #require(MacInstaller.parseHardware(json))
        #expect(hardware.udid == "00008122-001C11102186001C")
        #expect(hardware.model == "MacBook Air")
    }

    @Test("A Mac without a provisioning UDID cannot run iPad apps")
    func intel() {
        let json = Data(#"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","platform_UUID":"0A31343B"}]}"#.utf8)
        #expect(MacInstaller.parseHardware(json) == nil)
        #expect(MacInstaller.parseHardware(Data()) == nil)
    }

    @Test("Shows a laptop or desktop for this Mac")
    func symbol() {
        #expect(SavedDevice(id: "M", name: "Mac", model: "MacBook Air", isMac: true).symbolName == "laptopcomputer")
        #expect(SavedDevice(id: "M", name: "Mac", model: "Mac mini", isMac: true).symbolName == "desktopcomputer")
        #expect(SavedDevice(id: "P", name: "iPad", isPad: true).symbolName == "ipad")
    }
}

@Suite("Installing on this Mac")
struct MacInstallerTests {
    let root: URL
    let applications: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("keepalive-tests-\(UUID().uuidString)")
        applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A minimal app bundle with one file that tells versions apart.
    func product(_ version: String, bundleIdentifier: String = "com.example.App") throws -> URL {
        let app = root.appendingPathComponent("Build-\(version)/App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleIdentifier, "CFBundleName": "App"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
        try Data(version.utf8).write(to: app.appendingPathComponent(version))
        return app
    }

    func install(_ product: URL) throws -> URL {
        try MacInstaller.install(appAt: product, bundleIdentifier: "com.example.App", into: applications, registers: false)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @Test("Puts the app into a wrapper, as Xcode does")
    func wraps() throws {
        defer { cleanUp() }
        let wrapper = try install(try product("v1"))
        #expect(wrapper == applications.appendingPathComponent("App.app", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: wrapper.appendingPathComponent("Wrapper/App.app/v1").path))
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: wrapper.appendingPathComponent("WrappedBundle").path)
        #expect(link == "Wrapper/App.app")
        #expect(MacInstaller.bundleIdentifier(of: wrapper.appendingPathComponent("WrappedBundle")) == "com.example.App")
    }

    @Test("Replaces an earlier version completely")
    func replaces() throws {
        defer { cleanUp() }
        let wrapper = try install(try product("v1"))
        try install(try product("v2"))
        let app = wrapper.appendingPathComponent("Wrapper/App.app")
        #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("v2").path))
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("v1").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: applications.path)
        #expect(leftovers == ["App.app"])
    }

    @Test("Restores a missing link in the wrapper")
    func restoresLink() throws {
        defer { cleanUp() }
        let wrapper = try install(try product("v1"))
        try FileManager.default.removeItem(at: wrapper.appendingPathComponent("WrappedBundle"))
        try install(try product("v2"))
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: wrapper.appendingPathComponent("WrappedBundle").path)
        #expect(link == "Wrapper/App.app")
    }

    @Test("Leaves a different app with the same name alone", arguments: [true, false])
    func occupied(wrapped: Bool) throws {
        defer { cleanUp() }
        let other = try product("other", bundleIdentifier: "com.example.Other")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let existing = applications.appendingPathComponent("App.app")
        if wrapped {
            try MacInstaller.install(appAt: other, bundleIdentifier: "com.example.Other", into: applications, registers: false)
        } else {
            // A Mac app of the same name.
            try FileManager.default.copyItem(at: other, to: existing)
        }

        #expect(throws: MacInstallError.self) { try install(try product("v1")) }
        let marker = wrapped ? "Wrapper/App.app/other" : "other"
        #expect(FileManager.default.fileExists(atPath: existing.appendingPathComponent(marker).path))
    }
}
