import AppKit
import SwiftUI

/// Общее состояние шторки.
final class PanelState: ObservableObject {
    /// Форма раскрыта.
    @Published var expanded = false
    /// Содержимое видно (появляется чуть позже формы и исчезает раньше неё).
    @Published var showContent = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// Открыт дополнительный блок «Вентиляторы».
    @Published var showFans = false

    let baseHeight: CGFloat = 230
    let fansExtra: CGFloat = 104
    var expandedHeight: CGFloat { baseHeight + (showFans ? fansExtra : 0) }
}

/// Окно без рамки, которое живёт над строкой меню.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = PanelState()
    let stats = StatsModel()
    let claude = ClaudeModel()
    let login = LoginItem()
    /// Размер раскрытой панели.
    let expandedSize = CGSize(width: 640, height: 230)
    /// Запас вокруг панели, чтобы тень не обрезалась.
    let margin = CGSize(width: 40, height: 30)

    private var window: NotchWindow!
    private var screen: NSScreen!
    private var timer: Timer?
    private var leaveDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NotchWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // В свёрнутом виде окно пропускает клики сквозь себя, чтобы не мешать строке меню.
        window.ignoresMouseEvents = true

        let root = NotchView(
            state: state,
            stats: stats,
            claude: claude,
            login: login,
            expandedSize: expandedSize,
            onQuit: { NSApp.terminate(nil) }
        )
        .environment(\.colorScheme, .dark)
        window.contentView = NSHostingView(rootView: root)

        layout()
        window.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        // Реагируем на каждое движение мыши (события приходят с частотой экрана, до 120 Гц).
        // В простое ничего не считается, поэтому процессор не нагружается.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.tick() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.tick(); return e }

        // Редкая страховка: если курсор ушёл рывком (например, на другой экран) без событий над нами.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.state.expanded else { return }
            self.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?

    @objc private func screensChanged() { layout() }

    /// Находим экран с чёлкой и её размер, ставим окно по центру сверху.
    private func layout() {
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main ?? NSScreen.screens[0]
        screen = s

        var size = CGSize(width: 200, height: 32)
        if s.safeAreaInsets.top > 0,
           let left = s.auxiliaryTopLeftArea,
           let right = s.auxiliaryTopRightArea {
            size = CGSize(width: s.frame.width - left.width - right.width,
                          height: s.safeAreaInsets.top)
        } else {
            // Экран без чёлки: делаем «виртуальную» чёлку высотой со строку меню.
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            size.height = menuBar > 0 ? menuBar : 24
        }
        state.notchSize = size

        // Окно сразу с запасом под блок вентиляторов, чтобы не менять его размер во время анимации.
        let w = expandedSize.width + margin.width
        let h = state.baseHeight + state.fansExtra + margin.height
        let f = s.frame
        window.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), display: true)
    }

    private func tick() {
        guard let screen else { return }
        let p = NSEvent.mouseLocation
        let f = screen.frame
        let ns = state.notchSize

        // Зона чёлки (немного шире, и выходит за верхний край, чтобы ловить курсор у самого края).
        let notchRect = NSRect(x: f.midX - ns.width / 2 - 6, y: f.maxY - ns.height - 4,
                               width: ns.width + 12, height: ns.height + 8)
        // Зона раскрытой панели с небольшим запасом.
        let eh = state.expandedHeight
        let openRect = NSRect(x: f.midX - expandedSize.width / 2 - 12, y: f.maxY - eh - 12,
                              width: expandedSize.width + 24, height: eh + 16)

        if !state.expanded {
            if notchRect.contains(p) { setExpanded(true) }
        } else if openRect.contains(p) {
            leaveDate = nil
        } else if let d = leaveDate {
            if Date().timeIntervalSince(d) > 0.25 { setExpanded(false) }
        } else {
            leaveDate = Date()
        }
    }

    /// Номер текущей анимации: если курсор быстро вошёл и вышел, старые отложенные шаги игнорируются.
    private var animationID = 0

    /// Анимация в стиле Dynamic Island.
    private func setExpanded(_ value: Bool) {
        leaveDate = nil
        window.ignoresMouseEvents = !value
        stats.visible = value
        claude.visible = value
        animationID += 1
        let id = animationID

        if value {
            login.refresh()
            // 1. Форма мягко «раздувается» из чёлки, с едва заметной упругостью в конце.
            withAnimation(.spring(duration: 0.55, bounce: 0.14)) {
                state.expanded = true
            }
            // 2. Содержимое проявляется и чуть «опускается» на место, когда форма уже растёт.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.animationID == id else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0)) { self.state.showContent = true }
            }
        } else {
            // 1. Сначала мягко гасим содержимое.
            withAnimation(.easeOut(duration: 0.14)) { state.showContent = false }
            // 2. Затем форма плавно, без отскока, втягивается в чёлку.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.animationID == id else { return }
                withAnimation(.spring(duration: 0.45, bounce: 0)) {
                    self.state.expanded = false
                    self.state.showFans = false   // в следующий раз шторка откроется в обычном виде
                }
                self.stats.fansVisible = false
            }
        }
    }
}
