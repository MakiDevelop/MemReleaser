import Foundation
import ServiceManagement

enum LaunchAtLoginController {
    static func currentState() -> LaunchAtLoginState {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            return LaunchAtLoginState(
                isEnabled: true,
                isSupportedInCurrentBuild: true,
                needsApproval: false,
                title: "登入時自動啟動已開啟",
                detail: "下次登入 macOS 時，MemReleaser 會自動常駐。"
            )
        case .notRegistered:
            return LaunchAtLoginState(
                isEnabled: false,
                isSupportedInCurrentBuild: true,
                needsApproval: false,
                title: "登入時自動啟動未開啟",
                detail: "適合把它當作常駐守門員時開啟。"
            )
        case .requiresApproval:
            return LaunchAtLoginState(
                isEnabled: false,
                isSupportedInCurrentBuild: true,
                needsApproval: true,
                title: "需要你到系統設定核准",
                detail: "macOS 已收到註冊請求，但還需要你在 Login Items 裡允許。"
            )
        case .notFound:
            return .unavailable
        @unknown default:
            return LaunchAtLoginState(
                isEnabled: false,
                isSupportedInCurrentBuild: false,
                needsApproval: false,
                title: "無法判斷登入啟動狀態",
                detail: "這通常表示目前執行環境不是正式 app bundle。"
            )
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
        let service = SMAppService.mainApp

        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }

        return currentState()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
