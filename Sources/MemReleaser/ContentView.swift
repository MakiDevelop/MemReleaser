import Charts
import SwiftUI

struct ContentView: View {
    @Bindable var store: MonitorStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeroCard(store: store)
                    MetricGrid(snapshot: store.snapshot)
                    HistoryCard(store: store)
                    GrowthInsightsCard(store: store)
                    ControlsCard(store: store)
                    SuggestionsCard(store: store)
                    ProcessTable(store: store)
                    NotesCard()
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("MemReleaser")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.refreshNow() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("立即分析", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

private struct HeroCard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(store.snapshot.level.title, systemImage: store.snapshot.level.systemImage)
                        .font(.system(size: 28, weight: .bold))
                    Text(store.statusMessage)
                        .font(.headline)
                    Text("這不是假 RAM 清理器。MemReleaser 做的是：提前偵測壓力、抓出最該先關的 app、必要時安全請 app 正常結束。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.bytes(store.snapshot.availableBytes))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Swap \(Formatters.shortBytes(store.snapshot.swapUsedBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .background(backgroundGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var backgroundGradient: LinearGradient {
        switch store.snapshot.level {
        case .healthy:
            LinearGradient(colors: [Color(red: 0.77, green: 0.93, blue: 0.87), Color(red: 0.40, green: 0.71, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warning:
            LinearGradient(colors: [Color(red: 0.99, green: 0.87, blue: 0.64), Color(red: 0.96, green: 0.61, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .critical:
            LinearGradient(colors: [Color(red: 0.99, green: 0.73, blue: 0.65), Color(red: 0.86, green: 0.33, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct MetricGrid: View {
    let snapshot: MemorySnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "實體 RAM", value: Formatters.bytes(snapshot.physicalMemory), systemImage: "memorychip")
            MetricTile(title: "已使用", value: Formatters.bytes(snapshot.usedBytes), systemImage: "speedometer")
            MetricTile(title: "壓縮記憶體", value: Formatters.bytes(snapshot.compressedBytes), systemImage: "shippingbox")
            MetricTile(title: "App + Wired", value: Formatters.bytes(snapshot.appMemoryBytes), systemImage: "square.stack.3d.up")
            MetricTile(title: "快取 / Inactive", value: Formatters.bytes(snapshot.cachedBytes), systemImage: "internaldrive")
            MetricTile(title: "最後採樣", value: snapshot.sampledAt.formatted(date: .omitted, time: .standard), systemImage: "clock")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct HistoryCard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 30 分鐘")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("可用 / Swap 趨勢")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.history.count < 2 {
                Text("累積中…先讓它跑一會，這裡會出現歷史曲線。")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(store.history) { sample in
                        LineMark(
                            x: .value("時間", sample.timestamp),
                            y: .value("Available", gigabytes(sample.availableBytes))
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(store.history) { sample in
                        LineMark(
                            x: .value("時間", sample.timestamp),
                            y: .value("Swap", gigabytes(sample.swapUsedBytes))
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    }

                    RuleMark(y: .value("Warning", gigabytes(UInt64(Double(store.snapshot.physicalMemory) * 0.16))))
                        .foregroundStyle(.yellow.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    RuleMark(y: .value("Critical", gigabytes(UInt64(Double(store.snapshot.physicalMemory) * 0.08))))
                        .foregroundStyle(.red.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartLegend(.hidden)
                .frame(height: 220)

                HStack(spacing: 16) {
                    LegendPill(color: .green, title: "可用 \(Formatters.shortBytes(store.snapshot.availableBytes))")
                    LegendPill(color: .orange, title: "Swap \(Formatters.shortBytes(store.snapshot.swapUsedBytes))")
                    LegendPill(color: .yellow, title: "Warning 線")
                    LegendPill(color: .red, title: "Critical 線")
                }
                .font(.caption)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func gigabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824
    }
}

private struct LegendPill: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct GrowthInsightsCard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近 15 分鐘暴增中的 app")
                .font(.title3.weight(.semibold))

            if store.growthInsights.isEmpty {
                Text("目前沒有明顯暴增中的 app。這很重要，代表問題比較像高基線常駐，不是單一 leak 正在噴。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.growthInsights) { insight in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.displayName)
                                .font(.headline)
                            Text("\(insight.workloadKind.label) · \(insight.windowMinutes) 分鐘內增加 \(Formatters.shortBytes(UInt64(max(0, insight.deltaBytes))))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("現在 \(Formatters.shortBytes(insight.currentBytes))")
                            .font(.headline.monospacedDigit())
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ControlsCard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("策略")
                .font(.title3.weight(.semibold))
            Toggle("在 Warning / Critical 時送出通知", isOn: Binding(
                get: { store.notificationsEnabled },
                set: { store.toggleNotifications($0) }
            ))
            Toggle("Critical 時自動嘗試關閉隱藏且閒置 30 分鐘以上的 app", isOn: Binding(
                get: { store.autoReleaseOnCritical },
                set: { store.toggleAutoRelease($0) }
            ))
            .toggleStyle(.switch)

            HStack {
                Text("MemReleaser 自身占用：\(Formatters.shortBytes(store.selfResidentBytes))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(notificationDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("登入時自動啟動")
                        .font(.headline)
                    Text(store.launchAtLoginState.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.launchAtLoginState.isEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .disabled(!store.launchAtLoginState.isSupportedInCurrentBuild)
            }

            if store.launchAtLoginState.needsApproval || !store.launchAtLoginState.isSupportedInCurrentBuild {
                Button("打開 Login Items 設定") {
                    store.openLoginItemsSettings()
                }
            }

            HStack {
                Button("釋放前 2 名建議 app") {
                    store.releaseSuggestedApps(limit: 2, idleMinutesAtLeast: 20)
                }
                .buttonStyle(.borderedProminent)

                Button("匯出診斷 JSON") {
                    store.exportDiagnostics()
                }
                .buttonStyle(.bordered)

                Text("只會對可安全結束的 app 發送正常 terminate，不做強殺。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var notificationDetail: String {
        if let lastSentAt = store.lastNotificationSentAt {
            return "上次通知：\(Formatters.minutesSince(lastSentAt))"
        }
        return "通知尚未觸發"
    }
}

private struct SuggestionsCard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("現在最該先處理的 app")
                .font(.title3.weight(.semibold))

            if store.suggestions.isEmpty {
                Text("目前沒有明顯該動手的對象。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.suggestions.prefix(5)) { suggestion in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.app.displayName)
                                    .font(.headline)
                                Text(suggestion.app.workloadKind.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(suggestion.recommendation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Formatters.shortBytes(suggestion.app.residentBytes))
                                .font(.headline.monospacedDigit())
                            Button(store.isIgnored(suggestion.app) ? "取消忽略" : "忽略") {
                                store.toggleIgnore(suggestion.app)
                            }
                            .buttonStyle(.borderless)
                            if suggestion.app.canTerminate {
                                Button("請它結束") {
                                    store.terminate(suggestion)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Text(suggestion.reasons.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ProcessTable: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常駐記憶體排行")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    header("App")
                    header("記憶體")
                    header("類型")
                    header("程序數")
                    header("上次活躍")
                    header("狀態")
                    header("動作")
                }

                ForEach(store.apps.prefix(12)) { app in
                    Divider()
                        .gridCellColumns(7)

                    GridRow {
                        Text(app.displayName)
                        Text(Formatters.shortBytes(app.residentBytes))
                            .monospacedDigit()
                        Text(app.workloadKind.label)
                        Text("\(app.processCount)")
                            .monospacedDigit()
                        Text(Formatters.minutesSince(app.lastActiveAt))
                        Text(statusText(for: app))
                            .foregroundStyle(.secondary)
                        Button(store.isIgnored(app) ? "取消忽略" : "忽略") {
                            store.toggleIgnore(app)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func statusText(for app: AppMemoryUsage) -> String {
        if app.isFrontmost {
            return "前台"
        }
        if store.isIgnored(app) {
            return "已忽略"
        }
        if app.isHidden {
            return "隱藏"
        }
        if app.category == .commandLine {
            return "CLI"
        }
        if app.category == .system {
            return "系統"
        }
        return "背景"
    }
}

private struct NotesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("設計原則")
                .font(.title3.weight(.semibold))
            Text("1. macOS 沒有官方且可靠的『幫別的 app 釋放 RAM』API。真正有效的手段是：提前提醒、縮小工作集、請高佔用 app 正常退出。")
            Text("2. `purge` 類工具主要是清快取，不是根治；如果根因是瀏覽器多分頁、虛擬機、Docker、Xcode DerivedData、瀏覽器擴充套件或記憶體 leak，升到 128GB 也只是把爆點往後延。")
            Text("3. 這版把 Chrome / Brave 這類多進程 app 以整個 `.app` 聚合後再評估，避免只看到單一 helper。")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(18)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MenuBarDashboard: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.snapshot.level.title, systemImage: store.snapshot.level.systemImage)
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            Text("可用 \(Formatters.shortBytes(store.snapshot.availableBytes)) · Swap \(Formatters.shortBytes(store.snapshot.swapUsedBytes))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(store.suggestions.prefix(3)) { suggestion in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.app.displayName)
                        Text(Formatters.shortBytes(suggestion.app.residentBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if suggestion.app.canTerminate {
                        Button("結束") {
                            store.terminate(suggestion)
                        }
                    }
                }
            }

            if store.suggestions.isEmpty {
                Text("目前沒有需要先動手的 app。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            SettingsLink {
                Text("設定")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
