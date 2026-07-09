import Foundation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private(set) var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    private init() {}

    func toggle() {
        let newValue = !isEnabled
        isEnabled = newValue  // Optimistic update
        Task.detached {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                await MainActor.run { self.isEnabled = !newValue }
            }
        }
    }
}
