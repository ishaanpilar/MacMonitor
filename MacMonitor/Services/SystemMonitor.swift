import Foundation
import SwiftUI
import UserNotifications

@Observable
final class SystemMonitor {
    // MARK: - Constants
    private static let historyDurationSeconds: TimeInterval = 600  // 10 minutes
    private static let defaultPollInterval = 2

    // MARK: - Thermal State
    private(set) var pressure: ThermalPressure = .unknown
    private(set) var temperature: Double?           // headline temperature, always °C
    private(set) var temperatureSource: String?     // SMC key, "Average", or "HID"
    private(set) var fanSpeed: Double?              // Percentage 0-100%
    private(set) var hasFans: Bool = false
    private(set) var sensors: [String: Double] = [:]  // every discovered sensor, key -> °C

    // MARK: - CPU, Memory & Storage State
    private(set) var cpuUsage: CPUUsage?
    private(set) var memory: MemoryStats?
    private(set) var storage: StorageStats?

    // MARK: - Throttle (Intel only)
    private(set) var throttle: ThrottleInfo?
    var hasIntelThrottle: Bool { ThrottleReader.shared.isSupported }

    // MARK: - History
    private(set) var history: [HistoryEntry] = []
    private var timer: Timer?
    private var previousPressure: ThermalPressure = .unknown

    // MARK: - Preferences

    // Notifications
    var notifyOnHeavy: Bool = UserDefaults.standard.object(forKey: "notifyOnHeavy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnHeavy, forKey: "notifyOnHeavy") }
    }
    var notifyOnCritical: Bool = UserDefaults.standard.object(forKey: "notifyOnCritical") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnCritical, forKey: "notifyOnCritical") }
    }
    var notifyOnRecovery: Bool = UserDefaults.standard.object(forKey: "notifyOnRecovery") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notifyOnRecovery, forKey: "notifyOnRecovery") }
    }
    var notificationSound: Bool = UserDefaults.standard.object(forKey: "notificationSound") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notificationSound, forKey: "notificationSound") }
    }

    // Graphs
    var showFanSpeed: Bool = UserDefaults.standard.object(forKey: "showFanSpeed") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFanSpeed, forKey: "showFanSpeed") }
    }
    var showCPUGraph: Bool = UserDefaults.standard.object(forKey: "showCPUGraph") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showCPUGraph, forKey: "showCPUGraph") }
    }
    var showMemoryGraph: Bool = UserDefaults.standard.object(forKey: "showMemoryGraph") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMemoryGraph, forKey: "showMemoryGraph") }
    }

    // Temperature options
    var useFahrenheit: Bool = UserDefaults.standard.object(forKey: "useFahrenheit") as? Bool ?? false {
        didSet { UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit") }
    }
    /// false = report the hottest sensor (max), true = report the average.
    var averageTemperature: Bool = UserDefaults.standard.object(forKey: "averageTemperature") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(averageTemperature, forKey: "averageTemperature")
            updateState()
        }
    }
    /// Sensors the user picked to drive the headline temperature. Empty = automatic (CPU sensors).
    var selectedSensors: [String] = UserDefaults.standard.stringArray(forKey: "selectedSensors") ?? [] {
        didSet {
            UserDefaults.standard.set(selectedSensors, forKey: "selectedSensors")
            updateState()
        }
    }

    // Menu bar
    // swiftlint:disable:next line_length
    var showTemperatureInMenuBar: Bool = UserDefaults.standard.object(forKey: "showTemperatureInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showTemperatureInMenuBar, forKey: "showTemperatureInMenuBar") }
    }
    var showCPUInMenuBar: Bool = UserDefaults.standard.object(forKey: "showCPUInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showCPUInMenuBar, forKey: "showCPUInMenuBar") }
    }
    var showMemoryInMenuBar: Bool = UserDefaults.standard.object(forKey: "showMemoryInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showMemoryInMenuBar, forKey: "showMemoryInMenuBar") }
    }
    var showStorageUsedInMenuBar: Bool = UserDefaults.standard.object(forKey: "showStorageUsedInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showStorageUsedInMenuBar, forKey: "showStorageUsedInMenuBar") }
    }
    // swiftlint:disable:next line_length
    var showStorageAvailableInMenuBar: Bool = UserDefaults.standard.object(forKey: "showStorageAvailableInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showStorageAvailableInMenuBar, forKey: "showStorageAvailableInMenuBar") }
    }
    /// Stack the menu-bar readouts vertically (compact) instead of side by side.
    var compactMenuBar: Bool = UserDefaults.standard.object(forKey: "compactMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(compactMenuBar, forKey: "compactMenuBar") }
    }

    /// Poll interval in seconds (1...10). Restarts the timer when changed.
    var refreshInterval: Int = {
        let stored = UserDefaults.standard.integer(forKey: "refreshInterval")
        return stored >= 1 ? stored : defaultPollInterval
    }() {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }

    // MARK: - Derived

    /// All sensors sorted by name, for the sensor browser.
    var sortedSensors: [(name: String, value: Double)] {
        sensors
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isSensorSelected(_ name: String) -> Bool {
        selectedSensors.contains(name)
    }

    func toggleSensor(_ name: String) {
        if let index = selectedSensors.firstIndex(of: name) {
            selectedSensors.remove(at: index)
        } else {
            selectedSensors.append(name)
        }
    }

    var timeInEachState: [(pressure: ThermalPressure, duration: TimeInterval)] {
        guard history.count >= 2 else { return [] }

        var durations: [ThermalPressure: TimeInterval] = [:]

        for i in 0..<(history.count - 1) {
            let current = history[i]
            let next = history[i + 1]
            let duration = next.timestamp.timeIntervalSince(current.timestamp)
            durations[current.pressure, default: 0] += duration
        }

        if let last = history.last {
            let duration = Date().timeIntervalSince(last.timestamp)
            durations[last.pressure, default: 0] += duration
        }

        return durations.map { (pressure: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    var totalHistoryDuration: TimeInterval {
        guard let first = history.first else { return 0 }
        return Date().timeIntervalSince(first.timestamp)
    }

    // MARK: - Lifecycle

    init() {
        requestNotificationPermission()
        updateState()
        restartTimer()
    }

    deinit {
        timer?.invalidate()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(refreshInterval), repeats: true
        ) { [weak self] _ in
            self?.updateState()
        }
    }

    // MARK: - Sampling

    private func updateState() {
        let newPressure = ThermalPressureReader.shared.readPressure() ?? .unknown

        if newPressure != previousPressure {
            if shouldNotify(for: newPressure, previous: previousPressure) {
                sendThrottleNotification(pressure: newPressure)
            }
            let recovered = previousPressure.isThrottling && !newPressure.isThrottling
            if notifyOnRecovery && recovered && newPressure != .unknown {
                sendRecoveryNotification()
            }
            previousPressure = newPressure
        }
        pressure = newPressure

        // Discover all sensors, then compute the headline temperature from the user's selection.
        let allSensors = SMCReader.shared.readAllSensors()
        sensors = allSensors
        updateTemperature(from: allSensors)

        // Fan speed
        if let fan = SMCReader.shared.readFanSpeed() {
            fanSpeed = fan.percentage
            if !hasFans { hasFans = true }
        }

        // CPU load and memory
        if let usage = CPUReader.shared.readUsage() {
            cpuUsage = usage
        }
        memory = MemoryReader.shared.readMemory()
        storage = StorageReader.shared.readStorage()

        // Intel throttle (no-op on Apple Silicon)
        throttle = ThrottleReader.shared.read()

        recordHistory()
    }

    /// Selection logic: honour the user's chosen sensors, else CPU sensors, else all.
    private func updateTemperature(from allSensors: [String: Double]) {
        guard !allSensors.isEmpty else {
            // SMC yielded nothing (e.g. permissions) — fall back to the HID aggregate.
            if let hid = HIDTemperatureReader.shared.readCPUTemperature() {
                temperature = hid.value
                temperatureSource = "HID"
            } else {
                temperature = nil
                temperatureSource = nil
            }
            return
        }

        let cpuKeys = SMCReader.shared.cpuTemperatureKeys
        let cpuSensors = allSensors.filter { cpuKeys.contains($0.key) }

        let selected = selectedSensors.isEmpty
            ? [:]
            : allSensors.filter { selectedSensors.contains($0.key) }

        let chosen: [String: Double]
        if !selected.isEmpty {
            chosen = selected
        } else if !cpuSensors.isEmpty {
            chosen = cpuSensors
        } else {
            chosen = allSensors
        }

        guard !chosen.isEmpty else {
            temperature = nil
            temperatureSource = nil
            return
        }

        if averageTemperature {
            temperature = chosen.values.reduce(0, +) / Double(chosen.count)
            temperatureSource = "Average of \(chosen.count)"
        } else if let hottest = chosen.max(by: { $0.value < $1.value }) {
            temperature = hottest.value
            temperatureSource = hottest.key
        }
    }

    private func recordHistory() {
        let entry = HistoryEntry(
            pressure: pressure,
            temperature: temperature,
            fanSpeed: fanSpeed,
            cpuUsage: cpuUsage?.total,
            cpuSpeedLimit: throttle?.speedLimit.map(Double.init),
            memoryUsedFraction: memory?.usedFraction,
            memoryPressure: memory?.pressure,
            timestamp: Date()
        )
        history.append(entry)

        let cutoff = Date().addingTimeInterval(-Self.historyDurationSeconds)
        history.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Notifications

    private func shouldNotify(for pressure: ThermalPressure, previous: ThermalPressure) -> Bool {
        switch pressure {
        case .heavy:
            return notifyOnHeavy && !previous.isThrottling
        case .critical:
            return notifyOnCritical && previous != .critical
        default:
            return false
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendThrottleNotification(pressure: ThermalPressure) {
        let content = UNMutableNotificationContent()
        content.title = "Thermal Throttling"
        content.body = pressure == .critical
            ? "Your Mac is severely throttled!"
            : "Your Mac is being throttled (Heavy pressure)"
        if notificationSound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func sendRecoveryNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Thermal Pressure Recovered"
        content.body = "Your Mac is no longer being throttled"
        if notificationSound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

// MARK: - Formatting helpers

enum ByteFormat {
    /// Formats a byte count as GB with one decimal (e.g. "12.4 GB").
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)  // 1024^3
    }

    /// Compact form for the menu bar (e.g. "340G", "1.2T").
    static func compact(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1024 { return String(format: "%.1fT", gb / 1024) }
        return String(format: "%.0fG", gb)
    }
}
