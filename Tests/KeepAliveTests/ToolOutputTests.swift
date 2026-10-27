import Foundation
import Testing
@testable import KeepAlive

@Suite("Error messages")
struct DiagnosticsTests {
    @Test("Explains common failures in plain words", arguments: [
        ("error: No Accounts: Add a new account in Accounts settings.", "Add your Apple Account"),
        ("Your maximum App ID limit has been reached.", "ten new app IDs"),
        ("The maximum number of apps for free development profiles has been reached.", "three of your own apps"),
        ("Developer Mode is disabled on the device.", "Developer Mode"),
        ("ERROR: The device is locked.", "Unlock the device"),
        ("""
        ERROR: The developer disk image could not be mounted on this device. (com.apple.dt.CoreDeviceError error 12040 (0x2F08))
                       The operation failed because the device was still locked. (com.apple.dt.CoreDeviceError error 10003 (0x2713))
                       NSLocalizedFailureReason = The device is currently locked.
        """, "Unlock the device"),
        ("Timed out while attempting to establish tunnel", "could not be reached"),
        ("ERROR: A connection to this device could not be established. (com.apple.dt.CoreDeviceError error 4000 (0xFA0))", "could not be reached"),
        ("error: No profiles for 'com.example.App' were found", "No provisioning profile"),
    ])
    func knownProblems(output: String, expected: String) {
        #expect(Diagnostics.explain(output).contains(expected))
    }

    @Test("Recognizes a lost connection to the iPhone", arguments: [
        ("A connection to this device could not be established. (com.apple.dt.CoreDeviceError error 4000 (0xFA0))", true),
        ("Timed out while attempting to establish tunnel", true),
        ("Developer Mode is disabled on the device.", false),
    ])
    func unreachable(output: String, expected: Bool) {
        #expect(Diagnostics.isUnreachable(output) == expected)
    }

    @Test("Recognizes a locked iPhone", arguments: [
        ("The operation failed because the device was still locked. (com.apple.dt.CoreDeviceError error 10003 (0x2713))", true),
        ("ERROR: The device is locked.", true),
        ("Timed out while attempting to establish tunnel", false),
    ])
    func locked(output: String, expected: Bool) {
        #expect(Diagnostics.isLocked(output) == expected)
    }

    @Test("A locked or unreachable iPhone is waited for, a missing selection is not")
    func waiting() {
        #expect(RenewError.deviceLocked("iPhone").isWaitingForDevice)
        #expect(RenewError.deviceUnreachable("iPhone").isWaitingForDevice)
        #expect(!RenewError.noDeviceSelected.isWaitingForDevice)
    }

    @Test("Falls back to the first error line")
    func firstError() {
        let output = "note: building\n/path/File.swift:3:1: error: cannot find 'x' in scope\nerror: second"
        #expect(Diagnostics.explain(output) == "cannot find 'x' in scope")
    }

    @Test("Falls back to the last line without an error")
    func lastLine() {
        #expect(Diagnostics.explain("one\ntwo\n\n") == "two")
    }
}

@Suite("devicectl output")
struct DeviceParsingTests {
    let json = Data("""
        {"info":{"outcome":"success"},"result":{"devices":[
          {"identifier":"SIM-1",
           "connectionProperties":{"pairingState":"paired","transportType":"sameMachine","tunnelState":"connected"},
           "deviceProperties":{"name":"iPhone 17"},
           "hardwareProperties":{"reality":"simulated","platform":"iOS","marketingName":"iPhone 17","udid":"SIM-1"}},
          {"identifier":"SIM-2",
           "connectionProperties":{"pairingState":"paired","transportType":"sameMachine","tunnelState":"disconnected"},
           "deviceProperties":{"name":"iPhone 18 Pro"},
           "hardwareProperties":{"platform":"iOS","udid":"SIM-2"}},
          {"identifier":"PHONE-1",
           "connectionProperties":{"pairingState":"paired","transportType":"localNetwork","tunnelState":"connected"},
           "deviceProperties":{"name":"Work iPhone"},
           "hardwareProperties":{"reality":"physical","platform":"iOS","marketingName":"iPhone 16","udid":"0000-1"}},
          {"identifier":"PHONE-2",
           "connectionProperties":{"pairingState":"paired","transportType":"wired","tunnelState":"disconnected"},
           "deviceProperties":{"name":"Test iPad"},
           "hardwareProperties":{"reality":"physical","platform":"iOS","marketingName":"iPad Air","udid":"0000-2"}},
          {"identifier":"PHONE-3",
           "connectionProperties":{"pairingState":"paired","tunnelState":"unavailable"},
           "deviceProperties":{"name":"Old iPhone"},
           "hardwareProperties":{"reality":"physical","platform":"iOS","udid":"0000-3"}},
          {"identifier":"PHONE-4",
           "connectionProperties":{"pairingState":"unpaired","transportType":"wired","tunnelState":"connected"},
           "hardwareProperties":{"reality":"physical","platform":"iOS","udid":"0000-4"}},
          {"identifier":"PHONE-5",
           "connectionProperties":{"pairingState":"paired","transportType":"localNetwork","tunnelState":"disconnected"},
           "deviceProperties":{"name":"New iPhone"},
           "hardwareProperties":{"platform":"iOS","deviceType":"iPhone","productType":"iPhone17,3","udid":"0000-6"}},
          {"identifier":"WATCH-1",
           "connectionProperties":{"pairingState":"paired","transportType":"localNetwork","tunnelState":"connected"},
           "hardwareProperties":{"reality":"physical","platform":"watchOS","udid":"0000-5"}}
        ]}}
        """.utf8)

    @Test("Keeps only paired physical iPhones and iPads")
    func filtersDevices() throws {
        let devices = try DeviceService.parseDevices(json)
        #expect(devices.map(\.id) == ["PHONE-1", "PHONE-2", "PHONE-3", "PHONE-5"])
    }

    @Test("Reads name, model and connection")
    func readsDetails() throws {
        let devices = try DeviceService.parseDevices(json)
        let wifi = try #require(devices.first { $0.id == "PHONE-1" })
        #expect(wifi.name == "Work iPhone")
        #expect(wifi.model == "iPhone 16")
        #expect(wifi.udid == "0000-1")
        #expect(wifi.transport == .network)
        #expect(wifi.isReachable)

        #expect(!wifi.isPad)

        let cable = try #require(devices.first { $0.id == "PHONE-2" })
        #expect(cable.isPad, "Recognized by its model when the device type is missing")
        #expect(cable.transport == .wired)
        #expect(cable.isReachable, "A disconnected tunnel is opened on demand")
    }

    @Test("A device that cannot be seen is not reachable")
    func unavailable() throws {
        let gone = try #require(try DeviceService.parseDevices(json).first { $0.id == "PHONE-3" })
        #expect(!gone.isReachable)
        #expect(gone.name == "Old iPhone")
    }

    @Test("Accepts physical devices without a reality field (Xcode 27)")
    func missingReality() throws {
        let phone = try #require(try DeviceService.parseDevices(json).first { $0.id == "PHONE-5" })
        #expect(phone.isReachable)
        #expect(phone.transport == .network)
    }
}

@Suite("xcodebuild output")
struct JSONPayloadTests {
    @Test("Skips log lines before the JSON document")
    func skipsLogLines() throws {
        let output = """
            2026-10-06 12:00:00.000 xcodebuild[1:2] [MT] DVTPlugInLoading: Failed to load code for plug-in
            {
              "project" : { "schemes" : [ "App" ] }
            }
            """
        let object = try JSONSerialization.jsonObject(with: BuildService.jsonPayload(in: output)) as? [String: Any]
        #expect(object?["project"] != nil)
    }

    @Test("Finds arrays as well as objects")
    func arrays() throws {
        let data = BuildService.jsonPayload(in: "warning: something\n[ { \"target\" : \"App\" } ]")
        #expect((try JSONSerialization.jsonObject(with: data) as? [Any])?.count == 1)
    }

    @Test("Returns nothing when there is no JSON")
    func noJSON() {
        #expect(BuildService.jsonPayload(in: "error: no such scheme").isEmpty)
    }
}

@Suite("Running tools")
struct ShellTests {
    @Test("Captures output and exit status")
    func output() async throws {
        let result = try await Shell.run("/bin/sh", ["-c", "echo hello; echo oops >&2; exit 3"])
        #expect(result.status == 3)
        #expect(!result.succeeded)
        #expect(result.output.contains("hello"))
        #expect(result.output.contains("oops"))
    }

    @Test("Reports every line as it arrives")
    func lines() async throws {
        let collected = LineCollector()
        _ = try await Shell.run("/bin/sh", ["-c", "printf 'a\\nb\\nc'"]) { collected.add($0) }
        #expect(collected.lines == ["a", "b", "c"])
    }

    @Test("Passes environment variables")
    func environment() async throws {
        let result = try await Shell.run("/bin/sh", ["-c", "printf %s \"$KEEPALIVE_TEST\""],
                                         environment: ["KEEPALIVE_TEST": "value"])
        #expect(result.output == "value")
    }

    @Test("Stops commands that take too long")
    func timeout() async {
        await #expect(throws: ShellError.self) {
            try await Shell.run("/bin/sleep", ["5"], timeout: 0.5)
        }
    }

    @Test("Waits for short commands without the run loop")
    func blocking() {
        #expect(Shell.runBlocking("/usr/bin/true", []) == 0)
        #expect(Shell.runBlocking("/usr/bin/false", []) == 1)
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func add(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
