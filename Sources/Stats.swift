import Foundation
import IOKit
import IOKit.ps
import Darwin

/// Снимок показателей мака.
struct MacStats {
    var cpu: Double = 0                 // 0…1
    var cpuHistory: [Double] = []       // последние 60 секунд
    var cpuTemp: Double?                // °C
    var gpu: Double?                    // 0…1
    var memUsed: Double = 0             // байт
    var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var memFreePercent: Int?            // «свободно» по оценке ядра (основа давления памяти)
    var diskUsed: Double = 0
    var diskTotal: Double = 0
    var diskRead: Double = 0            // байт/с
    var diskWrite: Double = 0
    var netDown: Double = 0             // байт/с
    var netUp: Double = 0
    var battery: Int?                   // %
    var charging = false
    var onAC = false
    var gpuTemp: Double?                // °C
    var ssdTemp: Double?
    var batteryTemp: Double?
    var fans: [FanInfo] = []
}

/// Собирает показатели раз в секунду. Обновляет интерфейс только когда шторка открыта.
final class StatsModel: ObservableObject {
    @Published private(set) var stats = MacStats()

    /// Шторка открыта — публикуем данные в интерфейс.
    var visible = false {
        didSet { if visible && !oldValue { stats = current } }
    }

    private var current = MacStats()
    private var timer: Timer?
    private var tick = 0
    private var lastSample = Date()
    private var prevCPU: (busy: UInt64, total: UInt64)?
    private var prevNet: [String: (UInt32, UInt32)] = [:]
    private var prevDisk: (UInt64, UInt64)?
    private let temps = TempSensors()
    private let smc = SMC()

    /// Блок вентиляторов открыт — читаем SMC каждую секунду.
    var fansVisible = false {
        didSet {
            guard fansVisible, !oldValue else { return }
            readFansBlock()
            if visible { stats = current }
        }
    }

    init() {
        diskSpace()
        battery()
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        let now = Date()
        let dt = max(now.timeIntervalSince(lastSample), 0.1)
        lastSample = now
        tick += 1

        // Процессор
        if let c = cpuTicks() {
            if let p = prevCPU, c.total > p.total, c.busy >= p.busy {
                current.cpu = Double(c.busy - p.busy) / Double(c.total - p.total)
            }
            prevCPU = c
        }
        current.cpuHistory.append(current.cpu)
        if current.cpuHistory.count > 60 { current.cpuHistory.removeFirst() }

        memory()
        current.gpu = gpuUtilization()

        // Сеть
        let net = netCounters()
        if !prevNet.isEmpty {
            var down: UInt64 = 0, up: UInt64 = 0
            for (name, v) in net {
                if let p = prevNet[name] {
                    down += UInt64(v.0 &- p.0) // счётчики 32-битные — учитываем переполнение
                    up += UInt64(v.1 &- p.1)
                }
            }
            current.netDown = Double(down) / dt
            current.netUp = Double(up) / dt
        }
        prevNet = net

        // Диск: чтение/запись
        if let d = diskCounters() {
            if let p = prevDisk, d.0 >= p.0, d.1 >= p.1 {
                current.diskRead = Double(d.0 - p.0) / dt
                current.diskWrite = Double(d.1 - p.1) / dt
            }
            prevDisk = d
        }

        // Реже меняющиеся показатели
        if tick % 2 == 1 { current.cpuTemp = temps.cpuTemperature() }
        if visible && fansVisible { readFansBlock() }
        if tick % 5 == 0 { battery() }
        if tick % 30 == 0 { diskSpace() }

        if visible { stats = current }
    }

    private func readFansBlock() {
        current.fans = smc?.fans() ?? []
        current.gpuTemp = temps.gpuTemperature()
        current.ssdTemp = temps.ssdTemperature()
        current.batteryTemp = temps.batteryTemperature()
    }

    // MARK: - Процессор

    private func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let b = i * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]))
            let sys  = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]))
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        return (busy, total)
    }

    // MARK: - Память (считаем как «Мониторинг системы»: приложения + неперемещаемая + сжатая)

    private func memory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(getpagesize())
        let app = Double(vm.internal_page_count) - Double(vm.purgeable_count)
        current.memUsed = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 {
            current.memFreePercent = Int(level)
        }
    }

    // MARK: - Видеокарта

    private func gpuUtilization() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(it) }
        var result: Double?
        var s = IOIteratorNext(it)
        while s != 0 {
            if let props = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let u = (props["Device Utilization %"] as? NSNumber)?.doubleValue {
                result = max(result ?? 0, u / 100)
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return result
    }

    // MARK: - Сеть (только физические интерфейсы en*, чтобы VPN не считался дважды)

    private func netCounters() -> [String: (UInt32, UInt32)] {
        var result: [String: (UInt32, UInt32)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let a = p.pointee
            ptr = a.ifa_next
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  (a.ifa_flags & UInt32(IFF_UP)) != 0, let data = a.ifa_data else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (d.ifi_ibytes, d.ifi_obytes)
        }
        return result
    }

    // MARK: - Диск

    private func diskCounters() -> (UInt64, UInt64)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(it) }
        var r: UInt64 = 0, w: UInt64 = 0
        var s = IOIteratorNext(it)
        while s != 0 {
            if let st = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return (r, w)
    }

    private func diskSpace() {
        // Реальное свободное место (как df / iStat), без «очищаемого» — Finder его прибавляет.
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
           let total = v.volumeTotalCapacity,
           let free = v.volumeAvailableCapacity {
            current.diskTotal = Double(total)
            current.diskUsed = Double(total) - Double(free)
        }
    }

    // MARK: - Батарея

    private func battery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cur = d[kIOPSCurrentCapacityKey] as? Int, let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0 {
                current.battery = Int((Double(cur) / Double(mx) * 100).rounded())
            }
            current.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            current.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
    }
}

/// Температура процессора на Apple Silicon через системные HID-датчики
/// (закрытый интерфейс IOKit, тот же, что используют бесплатные мониторы). Если не доступен — nil.
final class TempSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFn = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (OpaquePointer) -> OpaquePointer?
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer, CFString) -> OpaquePointer?
    private typealias CopyEventFn = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> OpaquePointer?
    private typealias GetFloatFn = @convention(c) (OpaquePointer, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var client: OpaquePointer?
    private var servicesArray: CFArray?      // держим массив, чтобы службы оставались живы
    private var cpuServices: [OpaquePointer] = []

    init() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreate"),
              let m = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let cs = dlsym(h, "IOHIDEventSystemClientCopyServices"),
              let cp = dlsym(h, "IOHIDServiceClientCopyProperty"),
              let ce = dlsym(h, "IOHIDServiceClientCopyEvent"),
              let gf = dlsym(h, "IOHIDEventGetFloatValue") else { return }

        let create = unsafeBitCast(c, to: CreateFn.self)
        let setMatching = unsafeBitCast(m, to: SetMatchingFn.self)
        let copyServices = unsafeBitCast(cs, to: CopyServicesFn.self)
        let copyProperty = unsafeBitCast(cp, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(ce, to: CopyEventFn.self)
        getFloat = unsafeBitCast(gf, to: GetFloatFn.self)

        guard let client = create(kCFAllocatorDefault) else { return }
        self.client = client
        let match = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, match)

        guard let arrPtr = copyServices(client) else { return }
        let arr = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(arrPtr)).takeRetainedValue()
        servicesArray = arr

        // Названия датчиков зависят от чипа и версии macOS, поэтому есть запасные варианты.
        var acc: [OpaquePointer] = [], pmu: [OpaquePointer] = []
        var gpuMTR: [OpaquePointer] = [], gpuPMU: [OpaquePointer] = []
        for svc in arr as [AnyObject] {
            let sp = OpaquePointer(Unmanaged.passUnretained(svc).toOpaque())
            guard let namePtr = copyProperty(sp, "Product" as CFString) else { continue }
            let nameObj = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(namePtr)).takeRetainedValue()
            guard let name = nameObj as? String else { continue }
            if name.contains("ACC MTR Temp") { acc.append(sp) }                    // ядра процессора
            else if name.hasPrefix("PMU tdie") { pmu.append(sp) }                  // кристалл процессора
            else if name.hasPrefix("GPU MTR Temp") { gpuMTR.append(sp) }           // видеокарта
            else if name.hasPrefix("PMU TP"), name.hasSuffix("g") { gpuPMU.append(sp) } // видеокарта (M1 Pro, macOS 26)
            else if name.hasPrefix("NAND") { ssdServices.append(sp) }              // SSD
            else if name.hasPrefix("gas gauge battery") { batteryServices.append(sp) } // батарея
        }
        cpuServices = acc.isEmpty ? pmu : acc
        gpuServices = gpuMTR.isEmpty ? gpuPMU : gpuMTR
    }

    private var gpuServices: [OpaquePointer] = []
    private var ssdServices: [OpaquePointer] = []
    private var batteryServices: [OpaquePointer] = []

    func cpuTemperature() -> Double? { average(cpuServices) }
    func gpuTemperature() -> Double? { average(gpuServices) }
    func ssdTemperature() -> Double? { average(ssdServices) }
    func batteryTemperature() -> Double? { average(batteryServices) }

    private func average(_ services: [OpaquePointer]) -> Double? {
        guard let copyEvent, let getFloat, !services.isEmpty else { return nil }
        var sum = 0.0, n = 0.0
        for s in services {
            guard let ev = copyEvent(s, Self.temperatureEvent, 0, 0) else { continue }
            let v = getFloat(ev, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(ev)).release()
            if v > 0 && v < 130 { sum += v; n += 1 }
        }
        return n > 0 ? sum / n : nil
    }
}
