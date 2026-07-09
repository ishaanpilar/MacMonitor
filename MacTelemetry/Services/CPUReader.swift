import Foundation
import Darwin

/// Reads aggregate CPU load from the Mach host via `host_statistics(HOST_CPU_LOAD_INFO)`.
///
/// The kernel exposes cumulative tick counters (user / system / idle / nice). Usage is the
/// delta of those counters between two samples, so the first reading only seeds the baseline
/// and returns nil. Public API, no privileges required.
final class CPUReader {
    nonisolated(unsafe) static let shared = CPUReader()

    private var previous: host_cpu_load_info?

    private init() {}

    func readUsage() -> CPUUsage? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        defer { previous = info }
        guard let prev = previous else { return nil }  // first sample seeds the baseline

        // cpu_ticks tuple order: 0 = USER, 1 = SYSTEM, 2 = IDLE, 3 = NICE
        let userTicks = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let systemTicks = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idleTicks = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let niceTicks = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)

        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks
        guard totalTicks > 0 else { return nil }

        let user = (userTicks + niceTicks) / totalTicks * 100
        let system = systemTicks / totalTicks * 100
        let idle = idleTicks / totalTicks * 100

        return CPUUsage(total: min(100, user + system), user: user, system: system, idle: idle)
    }
}
