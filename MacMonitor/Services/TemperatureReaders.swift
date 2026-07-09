import Foundation
import IOKit

// MARK: - SMC Temperature Reader
// SMC approach based on https://github.com/exelban/stats/blob/master/SMC/
// Sensors based on https://github.com/exelban/stats/tree/master/Modules/Sensors

// swiftlint:disable:next large_tuple
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    // swiftlint:disable:next large_tuple
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    // swiftlint:disable:next large_tuple
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }
}

struct FanSpeed {
    let rpm: Double
    let percentage: Double  // 0-100%
}

struct TemperatureReading {
    let value: Double
    let source: String  // SMC key or "HID"
}

final class SMCReader {
    nonisolated(unsafe) static let shared = SMCReader()
    private static let temperatureKeyProbeRetryInterval: TimeInterval = 60

    private var conn: io_connect_t = 0
    private var isConnected = false

    // CPU/GPU temperature keys by chip generation
    // Source: https://github.com/exelban/stats/blob/a791a6c6a3840bcbe117690b8d3cff92179fc4aa/Modules/Sensors/values.swift#L329
    private let m1Keys = [
        "Tp09", "Tp0T",  // Efficiency CPU cores
        "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",  // Performance CPU cores
        "Tg05", "Tg0D", "Tg0L", "Tg0T"  // GPU
    ]
    // M1/M2 Pro/Max/Ultra use TC## keys for CPU cores instead of Tp##
    // Source: https://github.com/exelban/stats/issues/700
    private let mProMaxKeys = [
        // CPU
        "TC10", "TC11", "TC12", "TC13",
        "TC20", "TC21", "TC22", "TC23",
        "TC30", "TC31", "TC32", "TC33",
        "TC40", "TC41", "TC42", "TC43",
        "TC50", "TC51", "TC52", "TC53",
        // GPU
        "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0S", "Tg0T"
    ]
    private let m2Keys = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",  // Efficiency CPU cores
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j",  // Performance CPU cores
        "Tg0f", "Tg0j"  // GPU
    ]
    private let m3Keys = [
        "Te05", "Te0L", "Te0P", "Te0S",  // Efficiency CPU cores
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",  // Performance CPU cores
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"  // GPU
    ]
    private let m4Keys = [
        "Te05", "Te0S", "Te09", "Te0H",  // Efficiency CPU cores
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",  // Performance CPU cores
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"  // GPU
    ]

    // Cached fan count (0 = not yet read, -1 = no fans)
    private var cachedFanCount: Int?
    private var cachedTemperatureKeys: [String]?
    private var lastTemperatureKeyProbe: Date?

    // Full-sensor discovery cache (all "T" prefixed keys)
    private static let sensorDiscoveryInterval: TimeInterval = 60
    private var discoveredSensorKeys: [String]?
    private var lastSensorDiscovery: Date?

    private var allTemperatureKeys: [String] {
        var seenKeys = Set<String>()
        return (m1Keys + mProMaxKeys + m2Keys + m3Keys + m4Keys).filter { seenKeys.insert($0).inserted }
    }

    private init() {
        connect()
    }

    deinit {
        if isConnected {
            IOServiceClose(conn)
        }
    }

    private func connect() {
        guard let matchingDict = IOServiceMatching("AppleSMC") else { return }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == kIOReturnSuccess else { return }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }

        let openResult = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)

        isConnected = (openResult == kIOReturnSuccess)
    }

    func readCPUTemperature() -> TemperatureReading? {
        guard isConnected else { return nil }

        if let cachedTemperatureKeys, !cachedTemperatureKeys.isEmpty {
            if let reading = readTemperatureReading(from: cachedTemperatureKeys).reading {
                return reading
            }

            self.cachedTemperatureKeys = nil
        }

        if shouldSkipTemperatureKeyProbe {
            return nil
        }

        let result = readTemperatureReading(from: allTemperatureKeys)
        cachedTemperatureKeys = result.validKeys
        lastTemperatureKeyProbe = Date()

        return result.reading
    }

    // MARK: - Full sensor discovery (all "T" keys)
    // Enumerates every SMC key (via #KEY count + kSMCGetKeyFromIndex) and keeps those with a
    // "T" prefix. The key list is discovered once and cached, with values read each poll:
    // the key *list* is discovered once and re-probed every 60s, while values are read each
    // call. This guarantees new silicon never shows a blank temperature.

    /// The curated CPU/GPU key set, used to pick "CPU sensors" out of the full list.
    var cpuTemperatureKeys: Set<String> { Set(allTemperatureKeys) }

    /// Returns every discovered temperature sensor as SMC key -> °C.
    func readAllSensors() -> [String: Double] {
        guard isConnected else { return [:] }

        var result: [String: Double] = [:]
        for key in discoveredTemperatureKeys() {
            if let value = readTemperatureRaw(key: key), value > 1, value < 125 {
                result[key] = value
            }
        }
        return result
    }

    private func discoveredTemperatureKeys() -> [String] {
        if let discoveredSensorKeys,
           let lastSensorDiscovery,
           Date().timeIntervalSince(lastSensorDiscovery) < Self.sensorDiscoveryInterval {
            return discoveredSensorKeys
        }

        var keys: [String] = []
        let count = readKeyCount()
        if count > 0 {
            for index in 0..<count {
                guard let name = keyName(at: index) else { continue }
                if name.hasPrefix("T") {
                    keys.append(name)
                }
            }
        }

        discoveredSensorKeys = keys
        lastSensorDiscovery = Date()
        return keys
    }

    /// The value of the "#KEY" key is the total number of SMC keys (ui32, big-endian).
    private func readKeyCount() -> Int {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fromString: "#KEY")
        input.data8 = 9 // kSMCReadKeyInfo
        guard call(input: &input, output: &output) == kIOReturnSuccess else { return 0 }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5 // kSMCReadBytes
        guard call(input: &input, output: &output) == kIOReturnSuccess else { return 0 }

        return (Int(output.bytes.0) << 24) | (Int(output.bytes.1) << 16) |
               (Int(output.bytes.2) << 8) | Int(output.bytes.3)
    }

    /// Resolves the four-character key name at the given SMC index (kSMCGetKeyFromIndex).
    private func keyName(at index: Int) -> String? {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.data8 = 8 // kSMCGetKeyFromIndex
        input.data32 = UInt32(index)
        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let key = output.key
        guard key != 0 else { return nil }

        let chars = [
            UInt8((key >> 24) & 0xFF),
            UInt8((key >> 16) & 0xFF),
            UInt8((key >> 8) & 0xFF),
            UInt8(key & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii)
    }

    /// Decodes a key as a 4-byte float temperature without the CPU-range gate (used for discovery).
    private func readTemperatureRaw(key: String) -> Double? {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fromString: key)
        input.data8 = 9 // kSMCReadKeyInfo
        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        guard dataSize == 4 else { return nil }

        input.keyInfo.dataSize = dataSize
        input.data8 = 5 // kSMCReadBytes
        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let bitPattern = UInt32(output.bytes.0) | (UInt32(output.bytes.1) << 8) |
                        (UInt32(output.bytes.2) << 16) | (UInt32(output.bytes.3) << 24)
        return Double(Float(bitPattern: bitPattern))
    }

    /// Returns the average fan speed across all fans, or nil if no fans or reading failed
    func readFanSpeed() -> FanSpeed? {
        guard isConnected else { return nil }

        let fanCount = getFanCount()
        guard fanCount > 0 else { return nil }

        var totalRPM: Double = 0
        var totalPercentage: Double = 0
        var validReadings = 0

        for i in 0..<fanCount {
            if let actual = readFanValue(fan: i, key: "Ac"),
               let max = readFanValue(fan: i, key: "Mx"),
               max > 0 {
                totalRPM += actual
                totalPercentage += (actual / max) * 100
                validReadings += 1
            }
        }

        guard validReadings > 0 else { return nil }

        return FanSpeed(
            rpm: totalRPM / Double(validReadings),
            percentage: min(100, totalPercentage / Double(validReadings))
        )
    }

    /// Number of fans reported by SMC (0 if none / unsupported).
    var fanCount: Int { getFanCount() }

    /// The hardware min/max RPM for a given fan index, or nil if unavailable.
    func fanRange(fan: Int) -> (min: Double, max: Double)? {
        guard let minRPM = readFanValue(fan: fan, key: "Mn"),
              let maxRPM = readFanValue(fan: fan, key: "Mx"),
              maxRPM > minRPM else { return nil }
        return (minRPM, maxRPM)
    }

    private func getFanCount() -> Int {
        if let cached = cachedFanCount {
            return cached
        }

        guard let value = readUInt8(key: "FNum") else {
            cachedFanCount = 0
            return 0
        }

        cachedFanCount = Int(value)
        return Int(value)
    }

    private func readFanValue(fan: Int, key: String) -> Double? {
        // Fan keys are like "F0Ac", "F1Mx", etc.
        let fullKey = "F\(fan)\(key)"
        return readFloat(key: fullKey)
    }

    private var shouldSkipTemperatureKeyProbe: Bool {
        guard let cachedTemperatureKeys,
              cachedTemperatureKeys.isEmpty,
              let lastTemperatureKeyProbe else {
            return false
        }

        return Date().timeIntervalSince(lastTemperatureKeyProbe) < Self.temperatureKeyProbeRetryInterval
    }

    private func readTemperatureReading(from keys: [String]) -> (reading: TemperatureReading?, validKeys: [String]) {
        var maxTemp: Double = 0
        var maxKey: String = ""
        var validKeys: [String] = []

        for key in keys {
            guard let temp = readTemperature(key: key) else { continue }

            validKeys.append(key)
            if temp > maxTemp {
                maxTemp = temp
                maxKey = key
            }
        }

        let reading = maxTemp > 0 ? TemperatureReading(value: maxTemp, source: maxKey) : nil
        return (reading, validKeys)
    }

    private func readUInt8(key: String) -> UInt8? {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fromString: key)
        input.data8 = 9 // kSMCReadKeyInfo

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        guard dataSize >= 1 else { return nil }

        input.keyInfo.dataSize = dataSize
        input.data8 = 5 // kSMCReadBytes

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        return output.bytes.0
    }

    private func readFloat(key: String) -> Double? {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fromString: key)
        input.data8 = 9 // kSMCReadKeyInfo

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        input.keyInfo.dataSize = dataSize
        input.data8 = 5 // kSMCReadBytes

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        // flt type (4 bytes float) - used by Apple Silicon
        if dataSize == 4 {
            let bitPattern = UInt32(output.bytes.0) | (UInt32(output.bytes.1) << 8) |
                           (UInt32(output.bytes.2) << 16) | (UInt32(output.bytes.3) << 24)
            return Double(Float(bitPattern: bitPattern))
        }

        // fpe2 type (2 bytes fixed point) - used by some older keys
        if dataSize == 2 {
            let value = (UInt16(output.bytes.0) << 8) | UInt16(output.bytes.1)
            return Double(value) / 4.0
        }

        return nil
    }

    private func readTemperature(key: String) -> Double? {
        guard let value = readTemperatureRaw(key: key) else { return nil }
        return value > 20 && value < 150 ? value : nil
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        return IOConnectCallStructMethod(conn, 2, &input, inputSize, &output, &outputSize)
    }
}

// MARK: - HID Temperature Reader (fallback, lazy initialized)

final class HIDTemperatureReader {
    private typealias IOHIDEventSystemClientRef = OpaquePointer
    private typealias IOHIDServiceClientRef = OpaquePointer
    private typealias IOHIDEventRef = OpaquePointer

    private typealias CreateFunc = @convention(c) (CFAllocator?) -> IOHIDEventSystemClientRef?
    private typealias SetMatchingFunc = @convention(c) (IOHIDEventSystemClientRef, CFDictionary?) -> Void
    private typealias CopyServicesFunc = @convention(c) (IOHIDEventSystemClientRef) -> CFArray?
    private typealias CopyEventFunc = @convention(c) (IOHIDServiceClientRef, Int64, Int32, Int64) -> IOHIDEventRef?
    private typealias GetFloatValueFunc = @convention(c) (IOHIDEventRef, UInt32) -> Double
    private typealias ReleaseFunc = @convention(c) (OpaquePointer) -> Void

    private var create: CreateFunc?
    private var setMatching: SetMatchingFunc?
    private var copyServices: CopyServicesFunc?
    private var copyEvent: CopyEventFunc?
    private var getFloatValue: GetFloatValueFunc?
    private var release: ReleaseFunc?
    private var isInitialized = false

    private let kIOHIDEventTypeTemperature: Int64 = 15
    private let kIOHIDEventFieldTemperatureLevel: UInt32 = 0xf0000

    nonisolated(unsafe) static let shared = HIDTemperatureReader()

    private init() {}

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        guard let handle = dlopen(nil, RTLD_NOW) else { return }

        create = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCreate"), to: CreateFunc?.self)
        setMatching = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientSetMatching"), to: SetMatchingFunc?.self)
        copyServices = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCopyServices"), to: CopyServicesFunc?.self)
        copyEvent = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyEvent"), to: CopyEventFunc?.self)
        getFloatValue = unsafeBitCast(dlsym(handle, "IOHIDEventGetFloatValue"), to: GetFloatValueFunc?.self)
        release = unsafeBitCast(dlsym(handle, "CFRelease"), to: ReleaseFunc?.self)
    }

    /// Returns the maximum CPU die temperature (PMU tdie sensors)
    func readCPUTemperature() -> TemperatureReading? {
        ensureInitialized()

        guard let create, let setMatching, let copyServices, let copyEvent, let getFloatValue, let release else {
            return nil
        }

        guard let client = create(kCFAllocatorDefault) else { return nil }
        defer { release(client) }

        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        setMatching(client, matching as CFDictionary)

        guard let services = copyServices(client) else { return nil }
        // services (CFArray) is managed by Swift ARC

        var maxTemp: Double = 0
        let count = CFArrayGetCount(services)

        for i in 0..<count {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: IOHIDServiceClientRef.self)

            if let event = copyEvent(service, kIOHIDEventTypeTemperature, 0, 0) {
                let temp = getFloatValue(event, kIOHIDEventFieldTemperatureLevel)
                release(event)
                if temp > maxTemp && temp < 150 {
                    maxTemp = temp
                }
            }
        }

        return maxTemp > 0 ? TemperatureReading(value: maxTemp, source: "HID") : nil
    }
}
