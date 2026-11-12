import SwiftUI

/// Карточка «Мак»: сетка 3×2 с показателями.
struct MacStatsView: View {
    @ObservedObject var model: StatsModel
    var fansOpen = false
    var onCPUTap: (() -> Void)? = nil

    var body: some View {
        let s = model.stats
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            GridRow {
                StatTile(icon: "cpu", title: "CPU",
                         value: Fmt.pct(s.cpu),
                         sub: s.cpuTemp.map { "\(Int($0.rounded()))°C" } ?? "—",
                         tint: Fmt.loadColor(s.cpu),
                         subTint: (s.cpuTemp ?? 0) > 85 ? .orange : nil,
                         history: s.cpuHistory,
                         disclosure: fansOpen,
                         action: onCPUTap)
                StatTile(icon: "square.stack.3d.up", title: "GPU",
                         value: s.gpu.map(Fmt.pct) ?? "—",
                         sub: "видеокарта",
                         tint: Fmt.loadColor(s.gpu ?? 0))
                StatTile(icon: "memorychip", title: "Память",
                         value: "\(Fmt.gib(s.memUsed)) ГБ",
                         sub: "из \(Int((s.memTotal / 1_073_741_824).rounded())) ГБ",
                         tint: memoryColor(s.memFreePercent))
            }
            GridRow {
                StatTile(icon: "internaldrive", title: "SSD",
                         value: s.diskTotal > 0 ? Fmt.pct(s.diskUsed / s.diskTotal) : "—",
                         sub: "R \(Fmt.speed(s.diskRead))  W \(Fmt.speed(s.diskWrite))",
                         tint: Fmt.loadColor(s.diskTotal > 0 ? s.diskUsed / s.diskTotal : 0, warn: 0.85, crit: 0.95))
                StatTile(icon: "arrow.up.arrow.down", title: "Сеть",
                         value: "↓ \(Fmt.speed(s.netDown))",
                         sub: "↑ \(Fmt.speed(s.netUp))")
                StatTile(icon: batteryIcon(s), title: "Батарея",
                         value: s.battery.map { "\($0)%" } ?? "—",
                         sub: s.charging ? "заряжается" : (s.onAC ? "от сети" : "от батареи"),
                         tint: batteryColor(s))
            }
        }
    }

    private func memoryColor(_ free: Int?) -> Color {
        guard let free else { return .white }
        if free < 10 { return .red }
        if free < 20 { return .orange }
        return .white
    }

    private func batteryIcon(_ s: MacStats) -> String {
        if s.charging { return "battery.100percent.bolt" }
        switch s.battery ?? 100 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func batteryColor(_ s: MacStats) -> Color {
        if s.charging { return .green }
        guard let b = s.battery, !s.onAC else { return .white }
        if b <= 10 { return .red }
        if b <= 20 { return .orange }
        return .white
    }
}

/// Одна плитка показателя.
struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var sub: String? = nil
    var tint: Color = .white
    var subTint: Color? = nil
    var history: [Double]? = nil
    /// Если задано — плитка кликабельна и показывает стрелку (true = блок раскрыт).
    var disclosure: Bool? = nil
    var action: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let sub {
                Text(sub)
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(subTint ?? .white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottom) {
            if let history {
                Sparkline(values: history)
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 20)
                    .padding(.horizontal, 1)
                    .padding(.bottom, 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let disclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering || disclosure ? 0.8 : 0.35))
                    .rotationEffect(.degrees(disclosure ? 180 : 0))
                    .padding(7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(action != nil && (hovering || disclosure == true) ? 0.11 : 0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { h in
            guard action != nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
        }
        .onTapGesture { action?() }
        .help(action != nil ? "Вентиляторы и температура" : "")
    }
}

/// Мини-график (заливка) за последние 60 секунд.
struct Sparkline: Shape {
    var values: [Double]
    var capacity = 60

    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        let step = r.width / CGFloat(capacity - 1)
        func pt(_ i: Int) -> CGPoint {
            let x = r.maxX - CGFloat(values.count - 1 - i) * step
            let y = r.maxY - CGFloat(min(max(values[i], 0), 1)) * r.height
            return CGPoint(x: x, y: y)
        }
        p.move(to: CGPoint(x: pt(0).x, y: r.maxY))
        for i in values.indices { p.addLine(to: pt(i)) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Форматирование значений по-русски.
enum Fmt {
    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func gib(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_073_741_824).replacingOccurrences(of: ".", with: ",")
    }

    static func speed(_ b: Double) -> String {
        if b >= 1_000_000 {
            return String(format: "%.1f МБ/с", b / 1_000_000).replacingOccurrences(of: ".", with: ",")
        }
        if b >= 1_000 { return String(format: "%.0f КБ/с", b / 1_000) }
        return String(format: "%.0f Б/с", b)
    }

    static func loadColor(_ v: Double, warn: Double = 0.6, crit: Double = 0.85) -> Color {
        if v >= crit { return .red }
        if v >= warn { return .orange }
        return .white
    }
}
