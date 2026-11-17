import Foundation
import Cocoa

/// Single Responsibility: Manages reading and persisting Mole's configuration files on disk.
public final class FileConfigRepository: ConfigStoring {
    public let moleDirectory: String

    public init(moleDirectory: String = "\(NSHomeDirectory())/.config/mole") {
        self.moleDirectory = moleDirectory
    }

    public func readConfig(type: ConfigFileType) -> String {
        let path = filePath(for: type)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    public func saveConfig(type: ConfigFileType, content: String) throws -> String {
        let targetFile = filePath(for: type)
        try FileManager.default.createDirectory(atPath: moleDirectory, withIntermediateDirectories: true)
        try content.write(toFile: targetFile, atomically: true, encoding: .utf8)
        return targetFile
    }

    public func readCleanPreviewList() -> (content: String, path: String) {
        let path = "\(moleDirectory)/clean-list.txt"
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return (content, path)
    }

    private func filePath(for type: ConfigFileType) -> String {
        return "\(moleDirectory)/\(type.relativeFileName)"
    }
}

/// Single Responsibility: Executes synchronous shell commands and streaming Mole CLI tasks.
public final class MoleProcessExecutor: CommandExecuting {
    public let moleBinaryPath: String
    private let sanitizer: AnsiSanitizer
    private var runningProcess: Process?
    private let processLock = NSLock()

    public init(
        moleBinaryPath: String = "/usr/local/bin/mole",
        sanitizer: AnsiSanitizer = AnsiSanitizer()
    ) {
        self.moleBinaryPath = moleBinaryPath
        self.sanitizer = sanitizer
    }

    public func executeSync(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.environment = buildEnvironment(dryRun: false, stripColor: false)
        task.arguments = ["-c", command]

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    public func executeStreaming(
        subcommand: String,
        dryRun: Bool,
        onEvent: @escaping (CommandStreamEvent) -> Void
    ) {
        stopCurrentProcess()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let task = Process()
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = outPipe
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.environment = self.buildEnvironment(dryRun: dryRun, stripColor: true)

            let fullCommand = self.buildCommandString(subcommand: subcommand, dryRun: dryRun)
            task.arguments = ["-c", fullCommand]

            self.setRunningProcess(task)

            DispatchQueue.main.async {
                onEvent(.started(subcommand: subcommand, dryRun: dryRun, fullCommand: fullCommand))
            }

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                let cleanChunk = self?.sanitizer.sanitize(chunk) ?? chunk
                DispatchQueue.main.async {
                    onEvent(.output(subcommand: subcommand, chunk: cleanChunk))
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    onEvent(.output(
                        subcommand: subcommand,
                        chunk: "\nError launching process: \(error.localizedDescription)\n"
                    ))
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = nil
            let exitCode = task.terminationStatus
            self.setRunningProcess(nil)

            DispatchQueue.main.async {
                onEvent(.finished(subcommand: subcommand, dryRun: dryRun, exitCode: exitCode))
            }
        }
    }

    public func stopCurrentProcess() {
        processLock.lock()
        defer { processLock.unlock() }
        if let proc = runningProcess, proc.isRunning {
            proc.terminate()
        }
        runningProcess = nil
    }

    private func setRunningProcess(_ process: Process?) {
        processLock.lock()
        defer { processLock.unlock() }
        runningProcess = process
    }

    private func buildEnvironment(dryRun: Bool, stripColor: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = NSHomeDirectory()
        env["TERM"] = "dumb"
        if stripColor {
            env["NO_COLOR"] = "1"
        }
        if dryRun {
            env["MOLE_DRY_RUN"] = "1"
        }
        return env
    }

    private func buildCommandString(subcommand: String, dryRun: Bool) -> String {
        var cmdString = "\(moleBinaryPath) \(subcommand)"
        if dryRun && !cmdString.contains("--dry-run") {
            cmdString += " --dry-run"
        }
        if subcommand == "purge" && !dryRun && !cmdString.contains("--yes") {
            cmdString += " --yes"
        }
        return cmdString
    }
}

/// Single Responsibility: Handles native macOS Finder, Terminal, and App lifecycle integrations.
public final class MacOSIntegrationLauncher: ExternalIntegrationLaunching {
    private let commandExecutor: CommandExecuting

    public init(commandExecutor: CommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    public func openInTerminal(subcommand: String) {
        let cmd = subcommand.isEmpty ? "mo" : "mo \(subcommand)"
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "clear && \(cmd)"
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", scriptSource]
        try? task.run()
    }

    public func revealInFinder(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.selectFile(expanded, inFileViewerRootedAtPath: "")
    }

    public func terminateApplication() {
        commandExecutor.stopCurrentProcess()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
