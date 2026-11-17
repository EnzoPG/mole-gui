import Foundation

/// Domain representation of live system telemetry.
public struct SystemMetrics {
    public let diskTotalGB: Double
    public let diskFreeGB: Double
    public let diskUsedGB: Double
    public let diskUsedPercent: Double
    public let memoryTotalGB: Double
    public let memoryUsedGB: Double
    public let memoryUsedPercent: Double
    public let uptimeDays: Double
    public let touchIdEnabled: Bool

    public func toDictionary() -> [String: Any] {
        return [
            "disk_total_gb": String(format: "%.1f", diskTotalGB),
            "disk_free_gb": String(format: "%.0f", diskFreeGB),
            "disk_free_exact_gb": String(format: "%.2f", diskFreeGB),
            "disk_used_gb": String(format: "%.1f", diskUsedGB),
            "disk_used_percent": String(format: "%.1f", diskUsedPercent),
            "memory_total_gb": String(format: "%.1f", memoryTotalGB),
            "memory_used_gb": String(format: "%.2f", memoryUsedGB),
            "memory_used_short_gb": String(format: "%.1f", memoryUsedGB),
            "memory_used_percent": String(format: "%.1f", memoryUsedPercent),
            "uptime_days": String(format: "%.1f", uptimeDays),
            "touchid_enabled": touchIdEnabled
        ]
    }
}

/// Supported configuration file types managed by Mole.
public enum ConfigFileType: String, CaseIterable {
    case whitelistClean = "whitelist_clean"
    case whitelistOptimize = "whitelist_optimize"
    case purgePaths = "purge_paths"

    public var relativeFileName: String {
        switch self {
        case .whitelistClean:
            return "whitelist"
        case .whitelistOptimize:
            return "whitelist_optimize"
        case .purgePaths:
            return "purge_paths"
        }
    }
}

/// Incoming RPC request from the JavaScript frontend.
public struct BridgeRequest {
    public let reqId: String
    public let action: String
    public let payload: [String: Any]

    public init(reqId: String, action: String, payload: [String: Any]) {
        self.reqId = reqId
        self.action = action
        self.payload = payload
    }
}

/// Events emitted during a streaming CLI process execution.
public enum CommandStreamEvent {
    case started(subcommand: String, dryRun: Bool, fullCommand: String)
    case output(subcommand: String, chunk: String)
    case finished(subcommand: String, dryRun: Bool, exitCode: Int32)
}
