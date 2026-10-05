import AppKit

/// Finds an app icon to show next to each project, first from the built app,
/// otherwise from the project's asset catalog.
enum IconLocator {
    static let directory = BuildService.supportDirectory.appendingPathComponent("Icons", isDirectory: true)

    static func cachedIconURL(for app: ManagedApp) -> URL {
        directory.appendingPathComponent("\(app.id.uuidString).png")
    }

    static func cachedIcon(for app: ManagedApp) -> NSImage? {
        NSImage(contentsOf: cachedIconURL(for: app))
    }

    static func cacheIcon(for app: ManagedApp, builtApp: URL? = nil) {
        let source = builtApp.flatMap(iconInBuiltApp) ?? iconInProject(app.projectDirectory)
        guard let source else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = cachedIconURL(for: app)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
        if source.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: source)
        }
    }

    static func removeIcon(for app: ManagedApp) {
        try? FileManager.default.removeItem(at: cachedIconURL(for: app))
    }

    private static func iconInBuiltApp(_ appURL: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("AppIcon") && $0.pathExtension == "png" }
            .max { fileSize($0) < fileSize($1) }
    }

    private static func iconInProject(_ directory: URL) -> URL? {
        let skipped: Set<String> = ["Pods", "build", "DerivedData", "node_modules", ".git", ".build", "Carthage"]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if skipped.contains(url.lastPathComponent) || enumerator.level > 5 {
                enumerator.skipDescendants()
                continue
            }
            // Icon Composer documents, used by projects made for iOS 26 and later.
            if url.pathExtension == "icon", let rendered = renderIconDocument(url) {
                return rendered
            }
            guard url.pathExtension == "appiconset" else { continue }
            let images = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            if let largest = images.filter({ $0.pathExtension == "png" }).max(by: { fileSize($0) < fileSize($1) }) {
                return largest
            }
        }
        return nil
    }

    /// Renders an `.icon` document with Icon Composer's command line tool, which ships with Xcode.
    private static func renderIconDocument(_ document: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: document.appendingPathComponent("icon.json").path),
              let toolchain = try? Toolchain.resolve(override: nil)
        else { return nil }
        let ictool = toolchain.xcodeAppPath + "/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
        guard FileManager.default.isExecutableFile(atPath: ictool) else { return nil }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("KeepAlive-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ictool)
        process.arguments = [
            document.path, "--export-image", "--output-file", output.path,
            "--platform", "iOS", "--rendition", "Default",
            "--width", "128", "--height", "128", "--scale", "2",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
