import AppKit
import Foundation

/// Активная сессия Claude Code (из ~/.claude/sessions/*.json).
struct ClaudeSession: Identifiable {
    let id: String
    let pid: Int32
    let name: String
    let folder: String
    let status: String
    let remoteURL: URL?
    let updatedAt: Date
}

/// Счётчики токенов.
struct TokenTotals {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0, replies = 0
    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (a: TokenTotals, b: TokenTotals) -> TokenTotals {
        TokenTotals(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead,
                    replies: a.replies + b.replies)
    }
    static func - (a: TokenTotals, b: TokenTotals) -> TokenTotals {
        TokenTotals(input: a.input - b.input, output: a.output - b.output,
                    cacheWrite: a.cacheWrite - b.cacheWrite, cacheRead: a.cacheRead - b.cacheRead,
                    replies: a.replies - b.replies)
    }
}

/// Данные Claude Code для шторки. Обновляется только когда шторка открыта.
final class ClaudeModel: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var today = TokenTotals()
    @Published private(set) var week = TokenTotals()

    var visible = false {
        didSet { if visible && !oldValue { refreshSessions(); refreshTokens() } }
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var timer: Timer?
    private var tick = 0
    private var scanning = false

    // Состояние разбора журналов (только в фоновой очереди).
    private let queue = DispatchQueue(label: "notchpanel.claude-tokens", qos: .utility)
    private var offsets: [String: UInt64] = [:]
    private var contributions: [String: (day: Date, totals: TokenTotals)] = [:]
    private var perDay: [Date: TokenTotals] = [:]
    private var windowStart = Date.distantPast

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    init() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.visible else { return }
            self.tick += 1
            self.refreshSessions()
            if self.tick % 3 == 0 { self.refreshTokens() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Сессии

    func refreshSessions() {
        let dir = home.appendingPathComponent(".claude/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var list: [ClaudeSession] = []
        for f in files where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let pid = (j["pid"] as? NSNumber)?.int32Value,
                  kill(pid, 0) == 0 // процесс ещё жив
            else { continue }

            let cwd = j["cwd"] as? String ?? ""
            let folder: String
            if cwd == home.path || cwd.isEmpty { folder = "~" }
            else { folder = (cwd as NSString).lastPathComponent }

            var remote: URL?
            if let bridge = j["bridgeSessionId"] as? String, !bridge.isEmpty {
                remote = URL(string: "https://claude.ai/code/\(bridge)")
            }
            let updated = (j["updatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? .distantPast

            list.append(ClaudeSession(
                id: j["sessionId"] as? String ?? "\(pid)",
                pid: pid,
                name: j["name"] as? String ?? "сессия",
                folder: folder,
                status: j["status"] as? String ?? "",
                remoteURL: remote,
                updatedAt: updated))
        }
        let sorted = list.sorted { $0.updatedAt > $1.updatedAt }
        if sorted.map(\.id) != sessions.map(\.id) || sorted.map(\.status) != sessions.map(\.status) {
            sessions = sorted
        }
    }

    // MARK: - Токены (инкрементальный разбор журналов за 7 дней)

    func refreshTokens() {
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let (t, w) = self.scanTokens()
            DispatchQueue.main.async {
                self.today = t
                self.week = w
                self.scanning = false
            }
        }
    }

    private func scanTokens() -> (TokenTotals, TokenTotals) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        if start != windowStart { // наступил новый день — пересчитываем окно с нуля
            windowStart = start
            offsets = [:]; contributions = [:]; perDay = [:]
        }

        let root = home.appendingPathComponent(".claude/projects")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  let rv = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = rv.contentModificationDate, modified >= start,
                  let size = rv.fileSize else { continue }

            let path = url.path
            var off = offsets[path] ?? 0
            if UInt64(size) < off { off = 0 } // файл перезаписан
            guard UInt64(size) > off, let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            try? h.seek(toOffset: off)
            guard let data = try? h.readToEnd(), let lastNL = data.lastIndex(of: 0x0A) else { continue }

            let chunk = data[data.startIndex...lastNL] // только целые строки
            offsets[path] = off + UInt64(chunk.count)
            for line in chunk.split(separator: 0x0A) { parse(Data(line), start: start) }
        }

        let t = perDay[todayStart] ?? TokenTotals()
        let w = perDay.values.reduce(TokenTotals(), +)
        return (t, w)
    }

    private static let usageMarker = Data("\"usage\"".utf8)

    private func parse(_ line: Data, start: Date) {
        guard line.count > 64, line.range(of: Self.usageMarker) != nil,
              let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (j["type"] as? String) == "assistant",
              let msg = j["message"] as? [String: Any],
              let u = msg["usage"] as? [String: Any],
              let ts = j["timestamp"] as? String,
              let date = Self.isoFrac.date(from: ts) ?? Self.iso.date(from: ts),
              date >= start else { return }

        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        var t = TokenTotals(input: n("input_tokens"), output: n("output_tokens"),
                            cacheWrite: n("cache_creation_input_tokens"),
                            cacheRead: n("cache_read_input_tokens"), replies: 1)
        let day = Calendar.current.startOfDay(for: date)

        // Один ответ может быть записан несколькими строками с тем же id — берём самую полную.
        if let id = msg["id"] as? String {
            let key = id + "|" + (j["requestId"] as? String ?? "")
            if let old = contributions[key] {
                guard t.total > old.totals.total else { return }
                t.replies = 0
                perDay[old.day] = (perDay[old.day] ?? TokenTotals()) - old.totals
                var merged = t; merged.replies = old.totals.replies
                contributions[key] = (old.day, merged)
                perDay[old.day] = (perDay[old.day] ?? TokenTotals()) + merged
                return
            }
            contributions[key] = (day, t)
        }
        perDay[day] = (perDay[day] ?? TokenTotals()) + t
    }

    // MARK: - Действия

    /// Новая сессия Claude Code в Терминале (через .command-файл — без запроса прав на управление Терминалом).
    func newSession() {
        let fm = FileManager.default
        let dir = home.appendingPathComponent("Library/Application Support/NotchPanel")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("new-claude.command")

        // Ищем установленный Claude Code; если его нет — открываем страницу, где его скачать.
        let candidates = [home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            if let url = URL(string: "https://claude.com/claude-code") { NSWorkspace.shared.open(url) }
            return
        }
        let body = "#!/bin/zsh -l\ncd ~\nclear\nexec \"\(path)\"\n"
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func openApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "https://claude.ai/download") {
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
