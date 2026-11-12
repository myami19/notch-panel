import SwiftUI

/// Фирменный оранжевый Claude.
private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// Карточка «Claude Code»: кнопки, активные сессии, токены.
struct ClaudeView: View {
    @ObservedObject var model: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(claudeOrange)
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                IconButton(icon: "plus", help: "Новая сессия Claude Code в Терминале") { model.newSession() }
                IconButton(icon: "macwindow", help: "Открыть приложение Claude") { model.openApp() }
            }

            VStack(alignment: .leading, spacing: 3) {
                if model.sessions.isEmpty {
                    Text("Нет активных сессий")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                ForEach(model.sessions.prefix(3)) { s in
                    SessionRow(session: s) { if let u = s.remoteURL { model.open(u) } }
                }
                if model.sessions.count > 3 {
                    Text("ещё \(model.sessions.count - 3)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            tokens
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var tokens: some View {
        let t = model.today
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Сегодня")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(Fmt.compact(t.total))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("токенов")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text("\(t.replies) \(Fmt.plural(t.replies, "ответ", "ответа", "ответов")) · неделя \(Fmt.compact(model.week.total))")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help("""
        Сегодня — вход: \(Fmt.compact(t.input)), выход: \(Fmt.compact(t.output)), \
        кэш запись: \(Fmt.compact(t.cacheWrite)), кэш чтение: \(Fmt.compact(t.cacheRead))
        """)
    }
}

/// Строка сессии: статус, имя, папка, Remote Control.
struct SessionRow: View {
    let session: ClaudeSession
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        let (text, color) = statusInfo
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: session.status == "busy")
            Text(session.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
            Text(session.folder)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            Spacer(minLength: 2)
            if session.remoteURL != nil {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.55))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hovering && session.remoteURL != nil ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .help(session.remoteURL != nil ? "Открыть сессию в браузере (Remote Control)" : "Сессия в Терминале")
    }

    private var statusInfo: (String, Color) {
        switch session.status {
        case "busy": return ("работает", .green)
        case "idle": return ("ждёт", .white.opacity(0.5))
        case "waiting", "needs_input", "permission", "awaiting_input": return ("нужен ответ", .yellow)
        case "": return ("", .white.opacity(0.5))
        default: return (session.status, .white.opacity(0.5))
        }
    }
}

/// Маленькая круглая кнопка-иконка.
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.09)))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help(help)
    }
}

extension Fmt {
    /// 950 → «950», 12 300 → «12,3K», 2 100 000 → «2,1M».
    static func compact(_ v: Int) -> String {
        let d = Double(v)
        func f(_ x: Double, _ s: String) -> String {
            (x >= 100 ? String(format: "%.0f", x) : String(format: "%.1f", x))
                .replacingOccurrences(of: ".", with: ",") + s
        }
        if d >= 1_000_000_000 { return f(d / 1_000_000_000, "B") }
        if d >= 1_000_000 { return f(d / 1_000_000, "M") }
        if d >= 1_000 { return f(d / 1_000, "K") }
        return "\(v)"
    }

    /// Русское склонение: 1 ответ, 2 ответа, 5 ответов.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }
}
