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
            guard url.pathExtension == "appiconset" else { continue }
            let images = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            if let largest = images.filter({ $0.pathExtension == "png" }).max(by: { fileSize($0) < fileSize($1) }) {
                return largest
            }
        }
        return nil
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
