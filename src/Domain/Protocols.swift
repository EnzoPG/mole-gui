import Foundation

// MARK: - Telemetry Contracts (ISP / DIP)

/// Abstraction for collecting live hardware and OS metrics.
public protocol SystemMetricsProviding: AnyObject {
    func collectMetrics() -> SystemMetrics
}

// MARK: - Configuration Storage Contracts (ISP / DIP)

/// Abstraction for reading and writing Mole configuration files.
public protocol ConfigStoring: AnyObject {
    func readConfig(type: ConfigFileType) -> String
    func saveConfig(type: ConfigFileType, content: String) throws -> String
    func readCleanPreviewList() -> (content: String, path: String)
}

// MARK: - Process & Shell Execution Contracts (ISP / DIP)

/// Abstraction for synchronous and streaming command execution.
public protocol CommandExecuting: AnyObject {
    func executeSync(_ command: String) -> String
    func executeStreaming(
        subcommand: String,
        dryRun: Bool,
        onEvent: @escaping (CommandStreamEvent) -> Void
    )
    func stopCurrentProcess()
}

// MARK: - OS Integration Contracts (ISP / DIP)

/// Abstraction for interacting with macOS Terminal and Finder.
public protocol ExternalIntegrationLaunching: AnyObject {
    func openInTerminal(subcommand: String)
    func revealInFinder(path: String)
    func terminateApplication()
}

// MARK: - Bridge Messaging & Action Contracts (OCP / ISP / DIP)

/// Abstraction for sending events and resolving promises in the frontend view.
public protocol BridgeEventEmitting: AnyObject {
    func resolveRequest(reqId: String, data: [String: Any])
    func emitEvent(name: String, data: [String: Any])
}

/// Open/Closed Strategy contract: each bridge command implements this protocol.
public protocol BridgeActionHandling: AnyObject {
    var actionName: String { get }
    func handle(request: BridgeRequest, emitter: BridgeEventEmitting)
}
