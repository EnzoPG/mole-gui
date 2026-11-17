import Foundation

/// Open/Closed Principle (OCP) & Dependency Inversion Principle (DIP):
/// Dispatches incoming bridge requests to registered `BridgeActionHandling` strategies.
/// Adding new commands requires only registering a new handler—zero modification to the router.
public final class BridgeActionRouter {
    private var handlers: [String: BridgeActionHandling] = [:]

    public init(handlers: [BridgeActionHandling] = []) {
        for handler in handlers {
            register(handler)
        }
    }

    public func register(_ handler: BridgeActionHandling) {
        handlers[handler.actionName] = handler
    }

    public func route(request: BridgeRequest, emitter: BridgeEventEmitting) {
        guard let handler = handlers[request.action] else {
            emitter.resolveRequest(reqId: request.reqId, data: ["error": "Unknown action: \(request.action)"])
            return
        }
        handler.handle(request: request, emitter: emitter)
    }
}

// MARK: - Concrete Command Handlers (SRP + LSP)

/// Handles `getInitialState`: aggregates telemetry, version info, and config files.
public final class GetInitialStateHandler: BridgeActionHandling {
    public let actionName = "getInitialState"
    private let metricsProvider: SystemMetricsProviding
    private let configStore: ConfigStoring
    private let commandExecutor: CommandExecuting
    private let moleBinaryPath: String
    private let moleDir: String

    public init(
        metricsProvider: SystemMetricsProviding,
        configStore: ConfigStoring,
        commandExecutor: CommandExecuting,
        moleBinaryPath: String = "/usr/local/bin/mole",
        moleDir: String = "\(NSHomeDirectory())/.config/mole"
    ) {
        self.metricsProvider = metricsProvider
        self.configStore = configStore
        self.commandExecutor = commandExecutor
        self.moleBinaryPath = moleBinaryPath
        self.moleDir = moleDir
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var state = self.metricsProvider.collectMetrics().toDictionary()
            state["version_info"] = self.commandExecutor.executeSync("\(self.moleBinaryPath) --version")
            state["health_json"] = self.commandExecutor.executeSync("/bin/bash \(self.moleDir)/lib/check/health_json.sh")
            state["whitelist_clean"] = self.configStore.readConfig(type: .whitelistClean)
            state["whitelist_optimize"] = self.configStore.readConfig(type: .whitelistOptimize)
            state["purge_paths"] = self.configStore.readConfig(type: .purgePaths)
            emitter.resolveRequest(reqId: request.reqId, data: state)
        }
    }
}

/// Handles `runStreamCommand`: executes Mole CLI commands with live streaming output.
public final class RunStreamCommandHandler: BridgeActionHandling {
    public let actionName = "runStreamCommand"
    private let commandExecutor: CommandExecuting
    private let onCommandCompleted: () -> Void

    public init(commandExecutor: CommandExecuting, onCommandCompleted: @escaping () -> Void) {
        self.commandExecutor = commandExecutor
        self.onCommandCompleted = onCommandCompleted
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        guard let subcommand = request.payload["command"] as? String else { return }
        let dryRun = request.payload["dryRun"] as? Bool ?? false

        commandExecutor.executeStreaming(subcommand: subcommand, dryRun: dryRun) { [weak self] event in
            switch event {
            case let .started(cmd, isDry, fullCommand):
                emitter.emitEvent(name: "commandStarted", data: [
                    "command": cmd,
                    "dryRun": isDry,
                    "fullCommand": fullCommand
                ])
            case let .output(cmd, chunk):
                emitter.emitEvent(name: "commandOutput", data: [
                    "command": cmd,
                    "chunk": chunk
                ])
            case let .finished(cmd, isDry, exitCode):
                self?.onCommandCompleted()
                emitter.emitEvent(name: "commandFinished", data: [
                    "command": cmd,
                    "dryRun": isDry,
                    "exitCode": exitCode
                ])
                emitter.resolveRequest(reqId: request.reqId, data: [
                    "command": cmd,
                    "dryRun": isDry,
                    "exitCode": exitCode
                ])
            }
        }
    }
}

/// Handles `stopRunningCommand`: terminates any active Mole CLI process.
public final class StopRunningCommandHandler: BridgeActionHandling {
    public let actionName = "stopRunningCommand"
    private let commandExecutor: CommandExecuting

    public init(commandExecutor: CommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        commandExecutor.stopCurrentProcess()
        emitter.resolveRequest(reqId: request.reqId, data: ["stopped": true])
    }
}

/// Handles `analyzeDirectory`: runs `mole analyze --json` on a target folder.
public final class AnalyzeDirectoryHandler: BridgeActionHandling {
    public let actionName = "analyzeDirectory"
    private let commandExecutor: CommandExecuting
    private let moleBinaryPath: String

    public init(commandExecutor: CommandExecuting, moleBinaryPath: String = "/usr/local/bin/mole") {
        self.commandExecutor = commandExecutor
        self.moleBinaryPath = moleBinaryPath
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        let targetPath = (request.payload["path"] as? String) ?? NSHomeDirectory()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let expandedPath = (targetPath as NSString).expandingTildeInPath
            let jsonOut = self.commandExecutor.executeSync("\(self.moleBinaryPath) analyze --json \"\(expandedPath)\" 2>/dev/null")
            emitter.resolveRequest(reqId: request.reqId, data: ["json": jsonOut, "path": expandedPath])
        }
    }
}

/// Handles `getCleanPreviewList`: reads the dry-run preview file from `~/.config/mole/clean-list.txt`.
public final class GetCleanPreviewListHandler: BridgeActionHandling {
    public let actionName = "getCleanPreviewList"
    private let configStore: ConfigStoring

    public init(configStore: ConfigStoring) {
        self.configStore = configStore
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let preview = self.configStore.readCleanPreviewList()
            emitter.resolveRequest(reqId: request.reqId, data: ["content": preview.content, "path": preview.path])
        }
    }
}

/// Handles `saveConfigFile`: validates and persists whitelist or purge path configurations.
public final class SaveConfigFileHandler: BridgeActionHandling {
    public let actionName = "saveConfigFile"
    private let configStore: ConfigStoring

    public init(configStore: ConfigStoring) {
        self.configStore = configStore
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        guard let rawType = request.payload["type"] as? String,
              let configType = ConfigFileType(rawValue: rawType),
              let content = request.payload["content"] as? String else {
            emitter.resolveRequest(reqId: request.reqId, data: ["saved": false, "error": "Invalid config type"])
            return
        }

        do {
            let savedPath = try configStore.saveConfig(type: configType, content: content)
            emitter.resolveRequest(reqId: request.reqId, data: ["saved": true, "file": savedPath])
        } catch {
            emitter.resolveRequest(reqId: request.reqId, data: ["saved": false, "error": error.localizedDescription])
        }
    }
}

/// Handles `openInTerminal`: launches interactive Mole TUI commands in macOS Terminal.
public final class OpenInTerminalHandler: BridgeActionHandling {
    public let actionName = "openInTerminal"
    private let launcher: ExternalIntegrationLaunching

    public init(launcher: ExternalIntegrationLaunching) {
        self.launcher = launcher
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        let subcommand = (request.payload["command"] as? String) ?? ""
        launcher.openInTerminal(subcommand: subcommand)
        emitter.resolveRequest(reqId: request.reqId, data: ["launched": true])
    }
}

/// Handles `revealInFinder`: highlights a file or folder in macOS Finder.
public final class RevealInFinderHandler: BridgeActionHandling {
    public let actionName = "revealInFinder"
    private let launcher: ExternalIntegrationLaunching

    public init(launcher: ExternalIntegrationLaunching) {
        self.launcher = launcher
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        if let path = request.payload["path"] as? String {
            launcher.revealInFinder(path: path)
        }
        emitter.resolveRequest(reqId: request.reqId, data: ["ok": true])
    }
}

/// Handles `quitApp`: cleanly terminates running subprocesses and exits the application.
public final class QuitAppHandler: BridgeActionHandling {
    public let actionName = "quitApp"
    private let launcher: ExternalIntegrationLaunching

    public init(launcher: ExternalIntegrationLaunching) {
        self.launcher = launcher
    }

    public func handle(request: BridgeRequest, emitter: BridgeEventEmitting) {
        launcher.terminateApplication()
    }
}
