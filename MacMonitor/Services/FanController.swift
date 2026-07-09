import AppKit
import Observation

/// Drives manual SMC fan control through a small privileged helper tool rather than writing SMC
/// keys in-process. macOS returns `kIOReturnNotPrivileged` for unprivileged SMC *writes* on every
/// current release, Intel and Apple Silicon alike — only *reads* are unprivileged, which is why
/// temperature/fan-speed display always worked but direct control never will.
///
/// The helper (`macmonitor-fan-helper`, built alongside the app — see `Helper/`) is installed
/// once to `/Library/PrivilegedHelperTools`, owned by root with the setuid bit set, via a single
/// admin-authorization prompt. After that, invoking it needs no further prompts: the OS elevates
/// automatically because of the setuid bit.
///
/// Re-asserts the target on every `tick` because macOS's thermal daemon silently overwrites raw
/// SMC fan-target writes within a few seconds. Always fails safe back to Apple's automatic
/// curve — when the caller disables it, when any sensor crosses a critical temperature, and when
/// the app quits.
@Observable
final class FanController {
    nonisolated(unsafe) static let shared = FanController()

    static let minPercentage: Double = 30
    static let maxPercentage: Double = 100
    private static let criticalTemperature: Double = 100
    private static let helperName = "macmonitor-fan-helper"
    private static let installPath = "/Library/PrivilegedHelperTools/com.macmonitor.fanhelper"

    /// True once we've confirmed the SMC reports at least one controllable fan.
    let isSupported: Bool

    private(set) var isAuthorized: Bool
    private(set) var isRequestingAuthorization = false
    private(set) var authorizationError: String?

    private let fanCount: Int
    private var manualModeActive = false

    private init() {
        let count = SMCReader.shared.fanCount
        fanCount = count
        isSupported = count > 0
        isAuthorized = Self.helperIsUpToDate()

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

        guard isAuthorized else {
            // Auto-request only on the very first tick after enabling — if the user cancels or
            // it fails, don't hammer them with a password prompt every poll interval. They have
            // to explicitly retry (the "Grant Permission" button) to try again.
            if !isRequestingAuthorization && authorizationError == nil {
                requestAuthorization()
            }
            return
        }

        manualModeActive = true

        let percentage: Double
        if let hottestSensor, hottestSensor >= Self.criticalTemperature {
            percentage = 100
        } else {
            percentage = min(Self.maxPercentage, max(Self.minPercentage, targetPercentage))
        }

        for fan in 0..<fanCount {
            guard let range = SMCReader.shared.fanRange(fan: fan) else { continue }
            let rpm = range.min + (range.max - range.min) * (percentage / 100)
            runHelper(["set", "\(fan)", "\(Int(rpm.rounded()))"])
        }
    }

    /// Explicit user-initiated retry after a failed/cancelled authorization attempt.
    func retryAuthorization() {
        authorizationError = nil
        requestAuthorization()
    }

    private func disable() {
        guard manualModeActive, isAuthorized else {
            manualModeActive = false
            return
        }
        for fan in 0..<fanCount {
            runHelper(["auto", "\(fan)"])
        }
        manualModeActive = false
    }

    @discardableResult
    private func runHelper(_ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.installPath)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// True if a helper is already installed at the fixed path *and* matches the one bundled
    /// with this build — so app updates that change the helper trigger a fresh one-time install
    /// rather than silently running a stale binary forever.
    private static func helperIsUpToDate() -> Bool {
        guard let bundled = Bundle.main.url(forResource: helperName, withExtension: nil),
              FileManager.default.isExecutableFile(atPath: installPath) else {
            return false
        }
        return FileManager.default.contentsEqual(atPath: bundled.path, andPath: installPath)
    }

    private func requestAuthorization() {
        guard !isRequestingAuthorization else { return }

        guard let bundled = Bundle.main.url(forResource: Self.helperName, withExtension: nil) else {
            authorizationError = "The fan control helper is missing from the app bundle."
            return
        }

        isRequestingAuthorization = true
        authorizationError = nil

        let installDir = (Self.installPath as NSString).deletingLastPathComponent
        // swiftlint:disable:next line_length
        let command = "mkdir -p '\(installDir)' && cp '\(bundled.path)' '\(Self.installPath)' && chown root:wheel '\(Self.installPath)' && chmod 4755 '\(Self.installPath)'"
        // swiftlint:disable:next line_length
        let script = "do shell script \"\(command)\" with administrator privileges with prompt \"MacMonitor needs one-time permission to control your Mac's fans.\""

        // Neither closure captures `self` — both go through the static singleton — so there's
        // nothing non-Sendable being carried across the queue hop.
        DispatchQueue.global(qos: .userInitiated).async {
            var errorDict: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorDict)
            let succeeded = errorDict == nil && Self.helperIsUpToDate()

            DispatchQueue.main.async {
                FanController.shared.isRequestingAuthorization = false
                if succeeded {
                    FanController.shared.isAuthorized = true
                } else {
                    FanController.shared.authorizationError = "Permission was not granted."
                }
            }
        }
    }
}
