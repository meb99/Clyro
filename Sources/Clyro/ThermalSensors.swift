import Foundation
import IOKit

/// Liest CPU-Temperaturen aus dem SMC (AppleSMC). Der Zugriff ist rein lesend und braucht keine Adminrechte.
/// Schlägt er fehl (andere Chip-Generation, gesperrt), liefert `averageCPUTemperature()` `nil`
/// und die Oberfläche zeigt stattdessen nur den offiziellen Wärmezustand von macOS.
final class ThermalSensors: @unchecked Sendable {
    static let shared = ThermalSensors()

    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct KeyData {
        var key: UInt32 = 0
        var vers = Version()
        var pLimitData = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct SensorKey {
        let key: UInt32
        let info: KeyInfo
    }

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var sensorKeys: [SensorKey]?

    private init() {}

    func averageCPUTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }

        // Das Layout muss exakt der C-Struktur des SMC entsprechen.
        guard MemoryLayout<KeyData>.stride == 80, openIfNeeded() else { return nil }

        if sensorKeys == nil {
            sensorKeys = discoverSensorKeys()
        }
        let values = (sensorKeys ?? []).compactMap { sensor -> Double? in
            guard let value = readValue(of: sensor), value > 10, value < 120 else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - SMC-Zugriff

    private func openIfNeeded() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var handle: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &handle) == kIOReturnSuccess else { return false }
        connection = handle
        return true
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let status = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<KeyData>.stride,
            &output,
            &outputSize
        )
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func keyInfo(for key: UInt32) -> KeyInfo? {
        var input = KeyData()
        input.key = key
        input.data8 = 9
        return call(&input)?.keyInfo
    }

    private func readBytes(key: UInt32, info: KeyInfo) -> [UInt8]? {
        var input = KeyData()
        input.key = key
        input.keyInfo = info
        input.data8 = 5
        guard let output = call(&input) else { return nil }
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(min(info.dataSize, 32)))) }
    }

    private func discoverSensorKeys() -> [SensorKey] {
        guard let countInfo = keyInfo(for: Self.fourCC("#KEY")),
              let countBytes = readBytes(key: Self.fourCC("#KEY"), info: countInfo),
              countBytes.count == 4 else { return [] }
        let count = countBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count < 5000 else { return [] }

        var found: [SensorKey] = []
        for index in 0..<count {
            var input = KeyData()
            input.data8 = 8
            input.data32 = index
            guard let output = call(&input) else { continue }
            let name = Self.string(from: output.key)
            // CPU-Kerne: Apple Silicon (Tp…/Te…) und Intel (TC…).
            guard name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("TC"),
                  let info = keyInfo(for: output.key),
                  ["flt ", "sp78"].contains(Self.string(from: info.dataType)) else { continue }
            found.append(SensorKey(key: output.key, info: info))
        }
        return found
    }

    private func readValue(of sensor: SensorKey) -> Double? {
        guard let bytes = readBytes(key: sensor.key, info: sensor.info) else { return nil }
        switch Self.string(from: sensor.info.dataType) {
        case "flt " where bytes.count == 4:
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "sp78" where bytes.count == 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        default:
            return nil
        }
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from value: UInt32) -> String {
        let scalars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((value >> UInt32($0)) & 0xFF))) }
        return String(scalars)
    }
}
