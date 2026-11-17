import Foundation
import Darwin

/// Single Responsibility: Strips ANSI escape sequences and carriage returns from CLI output.
public struct AnsiSanitizer {
    private let regex: NSRegularExpression?

    public init() {
        self.regex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;?]*[A-Za-z]|\\r", options: [])
    }

    public func sanitize(_ input: String) -> String {
        guard let regex = regex else { return input }
        let range = NSRange(location: 0, length: input.utf16.count)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "")
    }
}

/// Single Responsibility: Gathers disk, Mach VM memory, uptime, and PAM Touch ID telemetry.
public final class SystemMetricsProvider: SystemMetricsProviding {
    private let homeDirectory: String
    private let pamPaths: [String]
    private let bytesPerGB: Double = 1024.0 * 1024.0 * 1024.0

    public init(
        homeDirectory: String = NSHomeDirectory(),
        pamPaths: [String] = ["/etc/pam.d/sudo", "/etc/pam.d/sudo_local"]
    ) {
        self.homeDirectory = homeDirectory
        self.pamPaths = pamPaths
    }

    public func collectMetrics() -> SystemMetrics {
        let disk = readDiskUsage()
        let memory = readMemoryUsage()
        let uptimeDays = ProcessInfo.processInfo.systemUptime / 86400.0
        let touchId = checkTouchIdEnabled()

        return SystemMetrics(
            diskTotalGB: disk.totalGB,
            diskFreeGB: disk.freeGB,
            diskUsedGB: disk.usedGB,
            diskUsedPercent: disk.usedPercent,
            memoryTotalGB: memory.totalGB,
            memoryUsedGB: memory.usedGB,
            memoryUsedPercent: memory.usedPercent,
            uptimeDays: uptimeDays,
            touchIdEnabled: touchId
        )
    }

    private func readDiskUsage() -> (totalGB: Double, freeGB: Double, usedGB: Double, usedPercent: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: homeDirectory),
              let totalBytes = attrs[.systemSize] as? Int64,
              let freeBytes = attrs[.systemFreeSize] as? Int64 else {
            return (0, 0, 0, 0)
        }

        let totalGB = Double(totalBytes) / bytesPerGB
        let freeGB = Double(freeBytes) / bytesPerGB
        let usedGB = max(0, totalGB - freeGB)
        let usedPct = totalGB > 0 ? (usedGB / totalGB) * 100.0 : 0.0
        return (totalGB, freeGB, usedGB, usedPct)
    }

    private func readMemoryUsage() -> (totalGB: Double, usedGB: Double, usedPercent: Double) {
        let totalMemBytes = ProcessInfo.processInfo.physicalMemory
        let totalMemGB = Double(totalMemBytes) / bytesPerGB

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()

        let kernReturn = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard kernReturn == KERN_SUCCESS else {
            return (totalMemGB, 0, 0)
        }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let usedBytes = active + wired + compressed
        let usedGB = usedBytes / bytesPerGB
        let memPct = totalMemGB > 0 ? (usedGB / totalMemGB) * 100.0 : 0.0

        return (totalMemGB, usedGB, memPct)
    }

    private func checkTouchIdEnabled() -> Bool {
        for path in pamPaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
               content.contains("pam_tid.so") {
                return true
            }
        }
        return false
    }
}
