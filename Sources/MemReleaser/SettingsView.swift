import SwiftUI

struct SettingsView: View {
    @Bindable var store: MonitorStore

    var body: some View {
        Form {
            Section("常駐設定") {
                Toggle("登入時自動啟動", isOn: Binding(
                    get: { store.launchAtLoginState.isEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .disabled(!store.launchAtLoginState.isSupportedInCurrentBuild)

                Text(store.launchAtLoginState.title)
                    .font(.headline)
                Text(store.launchAtLoginState.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if store.launchAtLoginState.needsApproval || !store.launchAtLoginState.isSupportedInCurrentBuild {
                    Button("打開 Login Items 設定") {
                        store.openLoginItemsSettings()
                    }
                }
            }

            Section("已忽略的 app") {
                if store.ignoredApps.isEmpty {
                    Text("目前沒有忽略中的 app。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.ignoredApps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.displayName)
                                Text("\(Formatters.shortBytes(app.residentBytes)) · \(app.workloadKind.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("取消忽略") {
                                store.toggleIgnore(app)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
