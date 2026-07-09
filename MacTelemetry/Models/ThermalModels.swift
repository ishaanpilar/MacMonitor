import Foundation
import SwiftUI

// MARK: - Thermal Pressure

enum ThermalPressure: String, Codable {
    case nominal
    case moderate
    case heavy
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }

    var isThrottling: Bool {
        switch self {
        case .heavy, .critical:
            return true
        default:
            return false
        }
    }

    var color: Color {
        switch self {
        case .nominal: return .green
        case .moderate: return .yellow
        case .heavy: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Memory Pressure
// Mirrors Activity Monitor's green / yellow / red memory-pressure graph.
// Source: sysctl `kern.memorystatus_vm_pressure_level` (1 = normal, 2 = warning, 4 = critical).

enum MemoryPressure: String, Codable {
    case normal
    case warning
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }

    var isElevated: Bool {
        self == .warning || self == .critical
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Memory Usage

/// A snapshot of physical-memory usage, in bytes, using Activity Monitor's accounting:
/// Used = App Memory + Wired + Compressed.
struct MemoryStats {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let free: UInt64
    let swapUsed: UInt64
    let pressure: MemoryPressure

    var used: UInt64 { min(app + wired + compressed, total) }

    /// Fraction of physical RAM in use, 0...1.
    var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

// MARK: - CPU Usage

/// Aggregate CPU load over the last sampling interval, as percentages that sum to ~100.
struct CPUUsage {
    let total: Double   // user + system, 0...100
    let user: Double
    let system: Double
    let idle: Double
}

// MARK: - Storage

/// Boot-volume storage in bytes. "Available" uses the Finder-style important-usage figure.
struct StorageStats {
    let total: UInt64
    let available: UInt64

    var used: UInt64 { total > available ? total - available : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

// MARK: - Throttle (Intel only)

/// Real throttle metrics reported by `pmset -g therm` on Intel Macs.
struct ThrottleInfo {
    let speedLimit: Int?      // % of max CPU speed (100 = not throttled)
    let schedulerLimit: Int?  // % scheduler limit
    let availableCPUs: Int?   // CPUs currently available to the scheduler

    var isThrottled: Bool {
        if let speedLimit { return speedLimit < 100 }
        return false
    }
}

// MARK: - Temperature formatting

enum TemperatureUnit {
    /// Formats a Celsius value in the user's chosen unit, e.g. "72°C" or "162°F".
    static func format(_ celsius: Double, fahrenheit: Bool) -> String {
        if fahrenheit {
            return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
        return "\(Int(celsius.rounded()))°C"
    }
}

// MARK: - History

struct HistoryEntry {
    let pressure: ThermalPressure
    let temperature: Double?         // Always stored in °C
    let fanSpeed: Double?            // Percentage 0-100%
    let cpuUsage: Double?            // Percentage 0-100%
    let cpuSpeedLimit: Double?       // Intel throttle %, 0-100 (nil on Apple Silicon)
    let memoryUsedFraction: Double?  // 0...1
    let memoryPressure: MemoryPressure?
    let timestamp: Date
}
