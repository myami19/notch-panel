import AppKit

// Отладка: `NotchPanel --fans` печатает вентиляторы.
if CommandLine.arguments.contains("--fans") {
    guard let smc = SMC() else { print("SMC недоступен"); exit(1) }
    for k in ["FNum", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "Ftst"] {
        if let r = smc.read(k) { print(k, r.type, r.bytes, smc.number(k).map { String($0) } ?? "") } else { print(k, "нет") }
    }
    for f in smc.fans() { print(f) }
    let t = TempSensors()
    print("CPU °C:", t.cpuTemperature() ?? -1, " GPU °C:", t.gpuTemperature() ?? -1,
          " SSD °C:", t.ssdTemperature() ?? -1, " BAT °C:", t.batteryTemperature() ?? -1)
    exit(0)
}

// Отладка: `NotchPanel --claude` печатает сессии и токены.
if CommandLine.arguments.contains("--claude") {
    let m = ClaudeModel()
    let t0 = Date()
    m.visible = true
    while m.today.replies == 0 && Date().timeIntervalSince(t0) < 20 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    print("scan:", String(format: "%.2fs", Date().timeIntervalSince(t0)))
    for s in m.sessions { print("session:", s.name, s.folder, s.status, s.remoteURL?.absoluteString ?? "-") }
    let t = m.today, w = m.week
    print("today: total \(t.total) in \(t.input) out \(t.output) cw \(t.cacheWrite) cr \(t.cacheRead) replies \(t.replies)")
    print("week:  total \(w.total) out \(w.output) replies \(w.replies)")
    exit(0)
}

// Отладка: `NotchPanel --dump` печатает показатели в терминал и выходит.
if CommandLine.arguments.contains("--dump") {
    let model = StatsModel()
    model.visible = true
    RunLoop.main.run(until: Date().addingTimeInterval(3.2))
    let s = model.stats
    print("""
    CPU: \(Fmt.pct(s.cpu))  temp: \(s.cpuTemp.map { String(format: "%.1f°C", $0) } ?? "nil")
    GPU: \(s.gpu.map(Fmt.pct) ?? "nil")
    RAM: \(Fmt.gib(s.memUsed)) / \(Fmt.gib(s.memTotal)) GiB, free level \(s.memFreePercent.map(String.init) ?? "nil")%
    SSD: \(Fmt.pct(s.diskTotal > 0 ? s.diskUsed / s.diskTotal : 0)) (\(Int(s.diskUsed / 1e9)) / \(Int(s.diskTotal / 1e9)) GB)  R \(Fmt.speed(s.diskRead)) W \(Fmt.speed(s.diskWrite))
    NET: ↓ \(Fmt.speed(s.netDown)) ↑ \(Fmt.speed(s.netUp))
    BAT: \(s.battery.map(String.init) ?? "nil")% charging=\(s.charging) AC=\(s.onAC)
    """)
    exit(0)
}

// Только один экземпляр: если шторка уже запущена — тихо выходим (код 0, служба не перезапустит).
let bundleID = Bundle.main.bundleIdentifier ?? "com.myami.notchpanel"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // без иконки в Dock
app.run()
