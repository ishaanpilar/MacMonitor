import Foundation

/// Reads the real CPU throttle metrics that macOS exposes on **Intel** Macs via `pmset -g therm`
/// (`CPU_Speed_Limit`, `CPU_Scheduler_Limit`, `CPU_Available_CPUs`). This is the one genuine
/// throttle measurement available without root — but only Intel reports it, and it costs a
/// subprocess, so the reader is a no-op on Apple Silicon (which has no equivalent field).
///
/// Only Intel Macs expose these fields; Apple Silicon has no equivalent.
final class ThrottleReader {
    nonisolated(unsafe) static let shared = ThrottleReader()

    /// True on Intel Macs. Determined once via `hw.optional.arm64`.
    let isSupported: Bool

    private init() {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        // On Apple Silicon the flag exists and is 1; on Intel the sysctl is absent.
        isSupported = !(result == 0 && value == 1)
    }

    func read() -> ThrottleInfo? {
        guard isSupported else { return nil }

        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-g", "therm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return nil
        }

        var speedLimit: Int?
        var schedulerLimit: Int?
        var availableCPUs: Int?

        let compact = output
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")

        for line in compact.split(separator: "\n") {
            let parts = line.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { continue }

            switch parts[0] {
            case "CPU_Speed_Limit": speedLimit = value
            case "CPU_Scheduler_Limit": schedulerLimit = value
            case "CPU_Available_CPUs": availableCPUs = value
            default: break
            }
        }

        guard speedLimit != nil || schedulerLimit != nil || availableCPUs != nil else {
            return nil
        }

        return ThrottleInfo(
            speedLimit: speedLimit,
            schedulerLimit: schedulerLimit,
            availableCPUs: availableCPUs
        )
    }
}
