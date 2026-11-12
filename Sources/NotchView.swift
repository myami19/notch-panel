import SwiftUI

struct NotchView: View {
    @ObservedObject var state: PanelState
    let stats: StatsModel
    let claude: ClaudeModel
    @ObservedObject var login: LoginItem
    let expandedSize: CGSize
    let onQuit: () -> Void

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let headerHeight: CGFloat = 20
    private let spacing: CGFloat = 12
    private let bottomPadding: CGFloat = 16

    var body: some View {
        let fullHeight = state.baseHeight + state.fansExtra
        let w = state.expanded ? expandedSize.width : state.notchSize.width
        let h = state.expanded ? state.expandedHeight : state.notchSize.height
        let r: CGFloat = state.expanded ? 28 : 10

        let shape = UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)

        // Слой полного размера стоит на месте и не перекладывается в каждом кадре:
        // анимируется только маска-форма, поэтому движение остаётся ровным на 120 Гц.
        ZStack(alignment: .top) {
            Color.black

            content
                .padding(.top, state.notchSize.height + 6)
                .padding(.horizontal, 22)
                .opacity(state.showContent ? 1 : 0)
                .offset(y: state.showContent ? 0 : -8)
                .allowsHitTesting(state.showContent)
        }
        .frame(width: expandedSize.width, height: fullHeight, alignment: .top)
        .mask(alignment: .top) {
            shape.frame(width: w, height: h)
        }
        .background(alignment: .top) {
            // Тень отдельно от содержимого и закэширована в один слой.
            shape
                .fill(Color.black)
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(state.expanded ? 0.35 : 0), radius: 10, y: 4)
                .compositingGroup()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Высота ряда карточек, чтобы базовая панель была ровно baseHeight.
    private var cardsHeight: CGFloat {
        state.baseHeight - (state.notchSize.height + 6) - headerHeight - spacing - bottomPadding
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header.frame(height: headerHeight)

            HStack(spacing: 12) {
                MacStatsView(model: stats, fansOpen: state.showFans, onCPUTap: toggleFans)
                    .frame(width: 372)
                ClaudeView(model: claude)
            }
            .frame(height: cardsHeight)

            FansView(model: stats)
                .frame(height: state.fansExtra - spacing - 4)
                .opacity(state.showFans ? 1 : 0)
                .offset(y: state.showFans ? 0 : -10)
                .allowsHitTesting(state.showFans)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onReceive(clock) { if state.showContent { now = $0 } } // часы тикают только когда панель открыта
        .onChange(of: state.showContent) { _, visible in if visible { now = Date() } }
    }

    private func toggleFans() {
        let open = !state.showFans
        stats.fansVisible = open
        withAnimation(.spring(duration: 0.5, bounce: open ? 0.1 : 0)) {
            state.showFans = open
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Button(action: login.toggle) {
                HStack(spacing: 4) {
                    Image(systemName: login.enabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Автозапуск")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(login.enabled ? 0.85 : 0.5))
            .help(login.viaAgent ? "Автозапуск настроен через install.sh"
                  : (login.enabled ? "Не запускать при входе в систему" : "Запускать при входе в систему"))
            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .help("Закрыть Notch Panel")
        }
    }

}
