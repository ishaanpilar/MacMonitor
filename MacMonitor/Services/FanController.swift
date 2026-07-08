import AppKit
import Foundation

/// Drives manual SMC fan control: forces every fan to a target percentage of its hardware
/// min-max RPM range while enabled, continuously re-asserting the target on each `tick` because
/// macOS's thermal daemon silently overwrites raw SMC fan-target writes within a few seconds.
///
/// Always fails safe back to Apple's automatic curve — when the caller disables it, when any
/// sensor crosses a critical temperature, and when the app quits.
final class FanController {
    nonisolated(unsafe) static let shared = FanController()

    static let minPercentage: Double = 30
    static let maxPercentage: Double = 100
    private static let criticalTemperature: Double = 100

    /// True once we've confirmed the SMC reports at least one controllable fan.
    let isSupported: Bool

    private let fanCount: Int
    private var manualModeActive = false

    private init() {
        let count = SMCReader.shared.fanCount
        fanCount = count
        isSupported = count > 0

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.disable()
        }
    }

    /// Call on every poll tick. `enabled`/`targetPercentage` reflect the user's current
    /// preference; `hottestSensor` is the max reading (°C) across all discovered sensors this tick.
    func tick(enabled: Bool, targetPercentage: Double, hottestSensor: Double?) {
        guard isSupported else { return }

        guard enabled else {
            if manualModeActive { disable() }
            return
        }

        if !manualModeActive {
            manualModeActive = SMCReader.shared.setManualFanControl(enabled: true, fanCount: fanCount)
        }

        let percentage: Double
        if let hottestSensor, hottestSensor >= Self.criticalTemperature {
            percentage = 100
        } else {
            percentage = min(Self.maxPercentage, max(Self.minPercentage, targetPercentage))
        }

        for fan in 0..<fanCount {
            guard let range = SMCReader.shared.fanRange(fan: fan) else { continue }
            let rpm = range.min + (range.max - range.min) * (percentage / 100)
            SMCReader.shared.writeFanTargetRPM(fan: fan, rpm: rpm)
        }
        // Re-assert manual mode too, in case macOS silently cleared the bit.
        SMCReader.shared.setManualFanControl(enabled: true, fanCount: fanCount)
    }

    private func disable() {
        SMCReader.shared.setManualFanControl(enabled: false, fanCount: fanCount)
        manualModeActive = false
    }
}
