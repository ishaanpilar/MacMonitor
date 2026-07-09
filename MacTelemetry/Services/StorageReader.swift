import Foundation

/// Reads boot-volume storage capacity. Uses `URLResourceValues`, the same source Finder uses,
/// so "available" reflects Finder's "Available" (important usage, i.e. after purgeable space).
final class StorageReader {
    nonisolated(unsafe) static let shared = StorageReader()

    private let volumeURL = URL(fileURLWithPath: "/")

    private init() {}

    func readStorage() -> StorageStats? {
        guard let values = try? volumeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity else {
            return nil
        }

        let available = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? 0
        return StorageStats(total: UInt64(total), available: available)
    }
}
