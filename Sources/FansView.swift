import SwiftUI

/// Блок «Вентиляторы» (только просмотр) + температуры.
struct FansView: View {
    @ObservedObject var model: StatsModel

    var body: some View {
        let s = model.stats
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Вентиляторы", systemImage: "fan")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(status(s.fans))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if s.fans.isEmpty {
                    Text("Нет данных о вентиляторах")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                ForEach(s.fans) { FanRow(fan: $0) }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 2) {
                Label("Температура", systemImage: "thermometer.medium")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.bottom, 2)
                tempRow("Процессор", s.cpuTemp)
                tempRow("Видеокарта", s.gpuTemp)
                tempRow("SSD", s.ssdTemp, warn: 60, crit: 70)
                tempRow("Батарея", s.batteryTemp, warn: 40, crit: 45)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 168)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))
    }

    private func status(_ fans: [FanInfo]) -> String {
        if fans.isEmpty { return "" }
        if fans.allSatisfy({ $0.rpm < 1 }) { return "остановлены · нагрузка низкая" }
        return "управляет система"
    }

    /// Строка температуры с подсветкой: зелёный — норма, жёлтый — близко к пределу, красный — слишком горячо.
    private func tempRow(_ title: String, _ t: Double?, warn: Double = 85, crit: Double = 95) -> some View {
        let color = tempColor(t, warn: warn, crit: crit)
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(t == nil ? 0 : 0.8), radius: 3)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(t.map { "\(Int($0.rounded()))°C" } ?? "—")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(t == nil ? 0 : 0.12))
        )
        .animation(.easeOut(duration: 0.4), value: color)
    }

    private func tempColor(_ t: Double?, warn: Double, crit: Double) -> Color {
        guard let t else { return .white.opacity(0.4) }
        if t >= crit { return .red }
        if t >= warn { return .yellow }
        return .green
    }
}

/// Строка вентилятора: номер, полоска 0…max с отметкой минимума, обороты.
struct FanRow: View {
    let fan: FanInfo

    var body: some View {
        HStack(spacing: 8) {
            Text("№\(fan.id + 1)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 22, alignment: .leading)

            GeometryReader { g in
                let maxRPM = max(fan.max, 1)
                let frac = CGFloat(min(fan.rpm / maxRPM, 1))
                let minX = g.size.width * CGFloat(fan.min / maxRPM)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, frac > 0.75 ? .orange : .blue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(g.size.width * frac, fan.rpm > 0 ? 4 : 0))
                    // Отметка минимальных оборотов (с них вентилятор стартует).
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1, height: 8)
                        .offset(x: minX)
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)

            Text(fan.rpm < 1 ? "стоит" : "\(Int(fan.rpm.rounded()).formatted()) об/мин")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)
        }
        .help("Диапазон: \(Int(fan.min)) – \(Int(fan.max)) об/мин")
    }
}
