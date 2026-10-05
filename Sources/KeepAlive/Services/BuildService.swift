import Foundation

enum BuildError: LocalizedError {
    case preBuildFailed(String)
    case buildFailed(String)
    case productMissing(String)
    case projectUnreadable(String)
    case noApplicationTarget

    var errorDescription: String? {
        switch self {
        case .preBuildFailed(let detail):
            return String(localized: "The pre-build command failed: \(detail)")
        case .buildFailed(let detail):
            return String(localized: "Build failed: \(detail)")
        case .productMissing(let name):
            return String(localized: "The build finished, but \(name) was not found.")
        case .projectUnreadable(let detail):
            return String(localized: "The project could not be read: \(detail)")
        case .noApplicationTarget:
            return String(localized: "This scheme does not build an iOS app.")
        }
    }
}

struct BuildService: Sendable {
    let toolchain: Toolchain

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeepAlive", isDirectory: true)
    }()

    static func derivedDataURL(for app: ManagedApp) -> URL {
        supportDirectory.appendingPathComponent("DerivedData/\(app.id.uuidString)", isDirectory: true)
    }

    static func removeBuildFiles(for app: ManagedApp) {
        try? FileManager.default.removeItem(at: derivedDataURL(for: app))
    }

    /// Builds the Release configuration with a freshly requested provisioning profile
    /// and returns the signed `.app`.
    func build(_ app: ManagedApp, onLine: @escaping @Sendable (String) -> Void) async throws -> URL {
        let command = app.preBuildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !command.isEmpty {
            let result = try await Shell.runScript(command, in: app.projectDirectory, onLine: onLine)
            guard result.succeeded else { throw BuildError.preBuildFailed(result.output.lastMeaningfulLine) }
        }

        let removed = ProfileInspector.removeCachedProfiles(for: app.bundleIdentifier)
        if removed > 0 { onLine("Removed \(removed) cached provisioning profile(s) for \(app.bundleIdentifier)") }

        let derivedData = Self.derivedDataURL(for: app)
        let result = try await Shell.run(
            Toolchain.xcrun,
            ["xcodebuild"] + projectArguments(for: app.projectURL) + [
                "-scheme", app.scheme,
                "-configuration", "Release",
                "-destination", "generic/platform=iOS",
                "-derivedDataPath", derivedData.path,
                "-allowProvisioningUpdates",
                "build",
            ],
            in: app.projectDirectory,
            environment: toolchain.environment,
            onLine: onLine
        )
        guard result.succeeded else { throw BuildError.buildFailed(Diagnostics.explain(result.output)) }

        let product = derivedData.appendingPathComponent("Build/Products/Release-iphoneos/\(app.productName)")
        guard FileManager.default.fileExists(atPath: product.path) else {
            throw BuildError.productMissing(app.productName)
        }
        return product
    }

    // MARK: - Reading projects

    struct ProjectInfo: Sendable {
        let projectURL: URL
        let schemes: [String]
    }

    struct SchemeInfo: Sendable {
        let bundleIdentifier: String
        let productName: String
        let displayName: String
    }

    /// Resolves what the user picked to a project or workspace. A CocoaPods or Flutter
    /// workspace next to the project wins, because the project alone will not build.
    static func resolveProject(at url: URL) -> URL? {
        let fileManager = FileManager.default
        switch url.pathExtension {
        case "xcworkspace":
            return url
        case "xcodeproj":
            let workspace = url.deletingPathExtension().appendingPathExtension("xcworkspace")
            return fileManager.fileExists(atPath: workspace.path) ? workspace : url
        default:
            let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            if let workspace = items.first(where: { $0.pathExtension == "xcworkspace" }) { return workspace }
            if let project = items.first(where: { $0.pathExtension == "xcodeproj" }) { return project }
            // Flutter and React Native keep the iOS project in a subfolder.
            let ios = url.appendingPathComponent("ios")
            return fileManager.fileExists(atPath: ios.path) ? resolveProject(at: ios) : nil
        }
    }

    func inspect(projectAt url: URL) async throws -> ProjectInfo {
        let result = try await Shell.run(
            Toolchain.xcrun,
            ["xcodebuild", "-list", "-json"] + projectArguments(for: url),
            in: url.deletingLastPathComponent(),
            environment: toolchain.environment,
            timeout: 120
        )
        let json = Self.jsonPayload(in: result.output)
        guard result.succeeded,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let container = (object["workspace"] ?? object["project"]) as? [String: Any]
        else { throw BuildError.projectUnreadable(Diagnostics.explain(result.output)) }

        let schemes = container["schemes"] as? [String] ?? []
        return ProjectInfo(projectURL: url, schemes: schemes)
    }

    func inspect(scheme: String, projectAt url: URL) async throws -> SchemeInfo {
        let result = try await Shell.run(
            Toolchain.xcrun,
            ["xcodebuild", "-showBuildSettings", "-json"] + projectArguments(for: url) + [
                "-scheme", scheme,
                "-configuration", "Release",
                "-destination", "generic/platform=iOS",
            ],
            in: url.deletingLastPathComponent(),
            environment: toolchain.environment,
            timeout: 180
        )
        let json = Self.jsonPayload(in: result.output)
        guard result.succeeded,
              let targets = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]]
        else { throw BuildError.projectUnreadable(Diagnostics.explain(result.output)) }

        let settings = targets
            .compactMap { $0["buildSettings"] as? [String: String] }
            .first { $0["PRODUCT_TYPE"] == "com.apple.product-type.application" && $0["WRAPPER_EXTENSION"] == "app" }
        guard let settings,
              let bundleIdentifier = settings["PRODUCT_BUNDLE_IDENTIFIER"],
              let productName = settings["FULL_PRODUCT_NAME"]
        else { throw BuildError.noApplicationTarget }

        let displayName = settings["INFOPLIST_KEY_CFBundleDisplayName"].flatMap { $0.isEmpty ? nil : $0 }
            ?? settings["PRODUCT_NAME"]
            ?? scheme
        return SchemeInfo(bundleIdentifier: bundleIdentifier, productName: productName, displayName: displayName)
    }

    private func projectArguments(for url: URL) -> [String] {
        [url.pathExtension == "xcworkspace" ? "-workspace" : "-project", url.path]
    }

    /// `xcodebuild` sometimes prints log lines before the JSON document, and those can
    /// contain brackets themselves. The document starts on a line beginning with `{` or `[`.
    private static func jsonPayload(in output: String) -> Data {
        for line in output.split(separator: "\n") where line.hasPrefix("{") || line.hasPrefix("[") {
            let candidate = Data(output[line.startIndex...].utf8)
            if (try? JSONSerialization.jsonObject(with: candidate)) != nil { return candidate }
        }
        return Data()
    }
}
