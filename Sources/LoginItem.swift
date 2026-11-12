import AppKit
import ServiceManagement

/// Переключатель «Запускать при входе» (системный механизм «Объекты входа»).
/// Если автозапуск уже настроен через install.sh (служба launchd) — просто показываем «включено».
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    let viaAgent: Bool

    init() {
        let agent = NSHomeDirectory() + "/Library/LaunchAgents/com.myami.notchpanel.plist"
        viaAgent = FileManager.default.fileExists(atPath: agent)
        refresh()
    }

    func refresh() {
        let on = viaAgent || SMAppService.mainApp.status == .enabled
        if on != enabled { enabled = on }
    }

    func toggle() {
        guard !viaAgent else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refresh()
    }
}
