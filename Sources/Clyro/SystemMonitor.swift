import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var memoryHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var downloadHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var diskActivityHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var temperatureHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var gpuHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoaded = false

    private var timer: Timer?
    private var previousCPU: CPUCounters?
    private var previousNetwork: NetworkCounters?
    private var previousDisk: DiskCounters?
    private var previousProcessTimes: [Int32: UInt64] = [:]
    private var previousSampleDate: Date?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let oldCPU = previousCPU
        let oldNetwork = previousNetwork
        let oldDisk = previousDisk
        let oldProcessTimes = previousProcessTimes
        let oldDate = previousSampleDate

        Task {
            var next = await Task.detached(priority: .utility) {
                SystemProbe.readSnapshot()
            }.value

            let now = Date()
            if let oldDate {
                let elapsed = max(0.25, now.timeIntervalSince(oldDate))
                next.cpuPercent = Self.cpuPercent(current: next.cpuCounters, previous: oldCPU)
                next.downloadBytesPerSecond = Self.bytesPerSecond(
                    current: next.networkCounters.receivedBytes,
                    previous: oldNetwork?.receivedBytes,
                    elapsed: elapsed
                )
                next.uploadBytesPerSecond = Self.bytesPerSecond(
                    current: next.networkCounters.sentBytes,
                    previous: oldNetwork?.sentBytes,
                    elapsed: elapsed
                )
                next.diskReadBytesPerSecond = Self.bytesPerSecond(
                    current: next.diskCounters.readBytes,
                    previous: oldDisk?.readBytes,
                    elapsed: elapsed
                )
                next.diskWriteBytesPerSecond = Self.bytesPerSecond(
                    current: next.diskCounters.writtenBytes,
                    previous: oldDisk?.writtenBytes,
                    elapsed: elapsed
                )
                next.processes = next.processes.map { process in
                    let previous = oldProcessTimes[process.id] ?? process.cpuTicks
                    let delta = process.cpuTicks >= previous ? process.cpuTicks - previous : 0
                    // proc_taskinfo reports accumulated CPU time in nanoseconds.
                    let percent = Double(delta) / 1_000_000_000 / elapsed * 100
                    let maximum = Double(max(1, ProcessInfo.processInfo.processorCount)) * 100
                    return SystemProcess(
                        id: process.id,
                        name: process.name,
                        cpuPercent: min(maximum, max(0, percent)),
                        memoryBytes: process.memoryBytes,
                        cpuTicks: process.cpuTicks,
                        executablePath: process.executablePath
                    )
                }
                .sorted {
                    if abs($0.cpuPercent - $1.cpuPercent) > 0.05 { return $0.cpuPercent > $1.cpuPercent }
                    return $0.memoryBytes > $1.memoryBytes
                }
            }

            let allProcessTimes = Dictionary(uniqueKeysWithValues: next.processes.map { ($0.id, $0.cpuTicks) })
            next.processCount = next.processes.count
            next.processes = Array(next.processes.prefix(60))
            previousCPU = next.cpuCounters
            previousNetwork = next.networkCounters
            previousDisk = next.diskCounters
            previousProcessTimes = allProcessTimes
            previousSampleDate = now
            snapshot = next
            append(next.cpuPercent, to: &cpuHistory)
            append(next.memoryPercent, to: &memoryHistory)
            append(next.downloadBytesPerSecond, to: &downloadHistory)
            append(next.diskReadBytesPerSecond + next.diskWriteBytesPerSecond, to: &diskActivityHistory)
            if let temperature = next.temperatureCelsius { append(temperature, to: &temperatureHistory) }
            append(next.gpuPercent ?? 0, to: &gpuHistory)
            hasLoaded = true
            isRefreshing = false
        }
    }

    private static func cpuPercent(current: CPUCounters, previous: CPUCounters?) -> Double {
        guard let previous,
              current.total >= previous.total,
              current.active >= previous.active else {
            guard current.total > 0 else { return 0 }
            return Double(current.active) / Double(current.total) * 100
        }
        let totalDelta = current.total - previous.total
        let activeDelta = current.active - previous.active
        guard totalDelta > 0 else { return 0 }
        return min(100, Double(activeDelta) / Double(totalDelta) * 100)
    }

    private static func bytesPerSecond(current: UInt64, previous: UInt64?, elapsed: TimeInterval) -> Double {
        guard let previous, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }
}

private enum SystemProbe {
    static func readSnapshot() -> SystemSnapshot {
        var result = SystemSnapshot()
        result.cpuCounters = cpuCounters()
        if result.cpuCounters.total > 0 {
            result.cpuPercent = Double(result.cpuCounters.active) / Double(result.cpuCounters.total) * 100
        }
        let memory = memoryUsage()
        result.memoryUsedBytes = memory.used
        result.memoryTotalBytes = memory.total
        let disk = diskUsage()
        result.diskUsedBytes = disk.used
        result.diskTotalBytes = disk.total
        result.networkCounters = networkCounters()
        result.diskCounters = diskCounters()
        result.smartStatus = SmartProbe.status()
        result.battery = batteryStatus()
        result.temperatureCelsius = ThermalSensors.shared.averageCPUTemperature()
        result.gpuTemperatureCelsius = ThermalSensors.shared.averageGPUTemperature()
        let gpu = gpuStatistics()
        result.gpuPercent = gpu.percent
        result.gpuCores = gpu.cores
        result.thermalState = ProcessInfo.processInfo.thermalState
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { result.loadAverage = loads[0] }
        result.processes = runningProcesses()
        result.chipName = sysctlString("machdep.cpu.brand_string")
            .replacingOccurrences(of: "Apple ", with: "")
        if result.chipName.isEmpty {
            result.chipName = sysctlString("hw.model")
        }
        result.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
        result.uptime = ProcessInfo.processInfo.systemUptime
        return result
    }

    private static func cpuCounters() -> CPUCounters {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return CPUCounters() }

        let ticks = withUnsafeBytes(of: info.cpu_ticks) { rawBuffer -> [UInt64] in
            rawBuffer.bindMemory(to: UInt32.self).map(UInt64.init)
        }
        guard ticks.count >= Int(CPU_STATE_MAX) else { return CPUCounters() }
        return CPUCounters(
            user: ticks[Int(CPU_STATE_USER)],
            system: ticks[Int(CPU_STATE_SYSTEM)],
            idle: ticks[Int(CPU_STATE_IDLE)],
            nice: ticks[Int(CPU_STATE_NICE)]
        )
    }

    private static func memoryUsage() -> (used: Int64, total: Int64) {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, total) }

        let pageSize = Int64(vm_kernel_page_size)
        let usedPages = Int64(stats.active_count)
            + Int64(stats.wire_count)
            + Int64(stats.compressor_page_count)
        return (min(total, max(0, usedPages * pageSize)), total)
    }

    private static func diskUsage() -> (used: Int64, total: Int64) {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? root.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return (max(0, total - available), total)
    }

    /// Auslastung und Kernanzahl der GPU aus der IORegistry (rein lesend).
    private static func gpuStatistics() -> (percent: Double?, cores: Int?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let info = acceleratorInfo(of: entry)
            IOObjectRelease(entry)
            if let info { return (info.percent, info.cores) }
            entry = IOIteratorNext(iterator)
        }
        return (nil, nil)
    }

    private static func acceleratorInfo(of entry: io_registry_entry_t) -> (percent: Double, cores: Int?)? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let statistics = properties["PerformanceStatistics"] as? [String: Any],
              let utilization = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue else { return nil }
        let cores = (properties["gpu-core-count"] as? NSNumber)?.intValue
        return (min(100, max(0, utilization)), cores)
    }

    /// Zyklen und Kapazität aus dem Akku-Eintrag der IORegistry (rein lesend).
    private static func smartBatteryHealth() -> (cycles: Int?, percent: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return (nil, nil) }

        let cycles = (properties["CycleCount"] as? NSNumber)?.intValue
        let maximum = ((properties["AppleRawMaxCapacity"] ?? properties["MaxCapacity"]) as? NSNumber)?.doubleValue ?? 0
        let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0
        // Ohne Rohwerte (mAh) ist MaxCapacity bereits ein Prozentwert und sagt nichts über den Verschleiß.
        let percent = (design > 0 && maximum > 100) ? Int((maximum / design * 100).rounded()) : nil
        return (cycles, percent.map { min(100, $0) })
    }

    private static func batteryStatus() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let rawSources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot()
        }

        for source in rawSources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue ?? 100
            let sourceState = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue ?? -1
            let remaining: String
            if sourceState == kIOPSACPowerValue {
                remaining = "Netzbetrieb"
            } else if minutes > 0 {
                remaining = String(format: "%d:%02d", minutes / 60, minutes % 60)
            } else {
                remaining = "Berechnung …"
            }

            let health = smartBatteryHealth()
            return BatterySnapshot(
                cycleCount: health.cycles,
                healthPercent: health.percent,
                percentage: maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current,
                isCharging: charging || sourceState == kIOPSACPowerValue,
                isPresent: true,
                timeRemaining: remaining
            )
        }
        return BatterySnapshot()
    }

    /// Summiert die Lese- und Schreibzähler aller Laufwerke aus der IORegistry (rein lesend).
    private static func diskCounters() -> DiskCounters {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return DiskCounters()
        }
        defer { IOObjectRelease(iterator) }

        var counters = DiskCounters()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let values = driveStatistics(of: entry)
            counters.readBytes += values.read
            counters.writtenBytes += values.written
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return counters
    }

    private static func driveStatistics(of entry: io_registry_entry_t) -> (read: UInt64, written: UInt64) {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let statistics = properties["Statistics"] as? [String: Any] else { return (0, 0) }
        let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
        let written = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        return (read, written)
    }

    private static func networkCounters() -> NetworkCounters {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return NetworkCounters() }
        defer { freeifaddrs(firstAddress) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               (interface.ifa_flags & UInt32(IFF_UP)) != 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received += UInt64(data.pointee.ifi_ibytes)
                sent += UInt64(data.pointee.ifi_obytes)
            }
            pointer = interface.ifa_next
        }
        return NetworkCounters(receivedBytes: received, sentBytes: sent)
    }

    private static func runningProcesses() -> [SystemProcess] {
        let capacity = max(256, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }

        var result: [SystemProcess] = []
        result.reserveCapacity(Int(count))
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var taskInfo = proc_taskinfo()
            let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let actualSize = withUnsafeMutablePointer(to: &taskInfo) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, expectedSize)
            }
            guard actualSize == expectedSize else { continue }

            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let nameLength = nameBuffer.withUnsafeMutableBytes { buffer in
                proc_name(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            guard nameLength > 0 else { continue }
            let name = String(cString: nameBuffer)
            let cpuTime = taskInfo.pti_total_user + taskInfo.pti_total_system
            let memory = Int64(clamping: taskInfo.pti_resident_size)
            // proc_pidpath expects a generously sized buffer; the C macro for its
            // maximum size is not imported consistently into every Swift SDK.
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let pathLength = pathBuffer.withUnsafeMutableBytes { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            let executablePath = pathLength > 0 ? String(cString: pathBuffer) : ""
            result.append(SystemProcess(
                id: pid,
                name: name,
                cpuPercent: 0,
                memoryBytes: memory,
                cpuTicks: cpuTime,
                executablePath: executablePath
            ))
        }
        return result.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

/// Liest den SMART-Status des Startlaufwerks über `diskutil` (rein lesend) und merkt ihn sich zehn Minuten.
private enum SmartProbe {
    private static let lock = NSLock()
    private static var cached: (status: SmartStatus, date: Date)?

    static func status() -> SmartStatus {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cached.date) < 600 { return cached.status }
        let value = read()
        cached = (value, Date())
        return value
    }

    private static func read() -> SmartStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return .unknown }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist["SMARTStatus"] as? String else { return .unknown }

        switch raw.lowercased() {
        case "verified": return .verified
        case "failing": return .failing
        case "not supported": return .unsupported
        default: return .unknown
        }
    }
}
