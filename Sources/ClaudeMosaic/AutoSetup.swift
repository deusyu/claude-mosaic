import Foundation
import ServiceManagement

enum AutoSetup {

    /// Run on every app launch: ensure hooks are installed and login item is registered.
    static func ensureSetup() {
        installHooksIfNeeded()
        registerLoginItem()
    }

    // MARK: - Hooks

    private static func installHooksIfNeeded() {
        let binary = ProcessInfo.processInfo.arguments[0]
        let hookCommand = "\(binary) hook"
        HookManager.installHook(command: hookCommand)
    }

    // MARK: - Login Item

    private static func registerLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if service.status != .enabled {
                try? service.register()
            }
        }
    }

    static func unregisterLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
    }
}
