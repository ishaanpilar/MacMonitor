import Foundation
import Darwin

/// Reads physical-memory usage and the system memory-pressure level. All public, no-privilege APIs:
///   - Usage breakdown: `host_statistics64(HOST_VM_INFO64)` -> `vm_statistics64`, in pages.
///   - Swap: `sysctl vm.swapusage` -> `xsw_usage`.
///   - Pressure: `sysctl kern.memorystatus_vm_pressure_level` (the green/yellow/red Activity Monitor shows).
final class MemoryReader {
    nonisolated(unsafe) static let shared = MemoryReader()

    private let pageSize: UInt64
    private let totalMemory: UInt64

    private init() {
        pageSize = UInt64(getpagesize())
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }

    func readMemory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize

        // Activity Monitor "App Memory" = internal anonymous pages minus purgeable.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize

        return MemoryStats(
            total: totalMemory,
            app: app,
            wired: wired,
            compressed: compressed,
            free: free,
            swapUsed: readSwapUsed(),
            pressure: readPressure()
        )
    }

    private func readSwapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return result == 0 ? usage.xsu_used : 0
    }

    private func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0 else { return .unknown }

        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }
}
