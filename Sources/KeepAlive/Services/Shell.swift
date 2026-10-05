import Foundation

struct ShellResult {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let command):
            return String(localized: "Could not run \(command).")
        case .timedOut(let command):
            return String(localized: "\(command) took too long and was stopped.")
        }
    }
}

/// Runs command line tools at utility priority, so builds prefer the efficiency cores
/// and never compete with what the user is doing.
enum Shell {
    static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 30 * 60,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.qualityOfService = .utility
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.append(data) }
        }

        let name = URL(fileURLWithPath: executable).lastPathComponent
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: ShellError.launchFailed(name))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        collector.timedOut = true
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
        collector.flush()

        if collector.timedOut { throw ShellError.timedOut(arguments.first ?? name) }
        try Task.checkCancellation()
        return ShellResult(status: status, output: collector.text)
    }

    /// Runs a user supplied command through a login shell, so tools like `flutter`
    /// installed via Homebrew or version managers are on the PATH.
    static func runScript(
        _ script: String,
        in directory: URL,
        environment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return try await run(shell, ["-l", "-c", script], in: directory, environment: environment, onLine: onLine)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = Data()
    private let onLine: (@Sendable (String) -> Void)?
    var timedOut = false

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        var lines: [String] = []
        if onLine != nil {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                lines.append(String(decoding: line, as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()
        if !rest.isEmpty { onLine?(String(decoding: rest, as: UTF8.self)) }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
