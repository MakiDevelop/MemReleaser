import Foundation

enum SuggestionEngine {
    static func suggestions(
        for apps: [AppMemoryUsage],
        snapshot: MemorySnapshot,
        ignoredKeys: Set<String> = []
    ) -> [AppSuggestion] {
        apps
            .filter { !ignoredKeys.contains($0.key) }
            .compactMap { app in
                let suggestion = buildSuggestion(for: app, snapshot: snapshot)
                return suggestion.score > 0 ? suggestion : nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.app.residentBytes > rhs.app.residentBytes
                }
                return lhs.score > rhs.score
            }
            .prefix(8)
            .map { $0 }
    }

    private static func buildSuggestion(for app: AppMemoryUsage, snapshot: MemorySnapshot) -> AppSuggestion {
        let residentGB = Double(app.residentBytes) / 1_073_741_824
        var score = residentGB * 12
        var reasons = ["占用 \(Formatters.shortBytes(app.residentBytes))", app.workloadKind.label]

        if app.processCount >= 4 {
            score += 4
            reasons.append("多進程常駐")
        }

        if app.isHidden {
            score += 10
            reasons.append("目前已隱藏")
        }

        if app.isFrontmost {
            score -= 30
            reasons.append("目前正在前台")
        }

        if let lastActiveAt = app.lastActiveAt {
            let idleMinutes = Date().timeIntervalSince(lastActiveAt) / 60
            if idleMinutes >= 60 {
                score += 15
                reasons.append("超過 1 小時沒切回")
            } else if idleMinutes >= 20 {
                score += 8
                reasons.append("超過 20 分鐘沒切回")
            } else if idleMinutes < 5 {
                score -= 10
            }
        } else if !app.isFrontmost {
            score += 5
            reasons.append("近期活躍度未知")
        }

        if !app.canTerminate {
            score -= 12
            reasons.append("無法安全代關閉")
        }

        if app.isSystemCritical {
            score = -100
        }

        if app.residentBytes < 400 * 1_024 * 1_024 {
            score -= 8
        }

        switch snapshot.level {
        case .healthy:
            score *= 0.85
        case .warning:
            score *= 1.1
        case .critical:
            score *= 1.35
        }

        let recommendation = recommendation(for: app)

        return AppSuggestion(app: app, score: score, reasons: reasons, recommendation: recommendation)
    }

    private static func recommendation(for app: AppMemoryUsage) -> String {
        switch app.workloadKind {
        case .browser:
            if app.canTerminate {
                return "先關這個瀏覽器或至少收掉整個 profile 視窗；分頁、擴充套件、工作區背景常駐比你想像更吃。"
            }
            return "瀏覽器通常要靠收分頁、停用 profile 視窗、關掉重擴充套件，不是清 cache。"
        case .virtualMachine:
            return "這類最有效的是 suspend / stop guest 或容器引擎；它們會直接鎖住一大塊 RAM。"
        case .developerTool:
            return "優先收掉不用的 workspace、Simulator、LLM 工具或大型索引流程；這類常把 swap 推高。"
        case .communication:
            if app.canTerminate {
                return "通訊 app 不是每次都最肥，但閒置一整天時可以先退出，尤其有大檔附件或通話後。"
            }
            return "通訊類通常不是第一刀，除非它剛經歷大型會議、附件同步或畫面分享。"
        case .terminal:
            return "檢查是不是背景 dev server、Python job、local model 或同步程序沒收；CLI 常是看不見的常駐戶。"
        case .system:
            return "系統程序只觀察，不動手。"
        case .unknown:
            if app.canTerminate {
                return app.isHidden
                    ? "先嘗試請它正常結束，通常是最安全的釋放方式。"
                    : "如果現在不需要這個 app，可以先退出換回可用記憶體。"
            }
            return "這類程序建議手動處理；app 會把它列為觀察對象，但不自動動手。"
        }
    }
}
