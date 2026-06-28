import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: KindlePilotViewModel
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Form {
            Section(L("界面")) {
                Picker(L("语言"), selection: $languageStore.preference) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Text(L("默认跟随系统语言。切换后会立即应用到界面。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("连接")) {
                TextField("Kindle IP", text: $model.settings.host)
                    .textFieldStyle(.roundedBorder)

                TextField(L("端口"), value: $model.settings.port, format: .number)
                    .textFieldStyle(.roundedBorder)

                TextField(L("用户名"), text: $model.settings.username)
                    .textFieldStyle(.roundedBorder)

                LabeledContent(L("认证方式")) {
                    Text(L("密码"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("认证")) {
                SecureField(L("密码"), text: $model.password)
                    .textFieldStyle(.roundedBorder)
            }

            Section(L("设备")) {
                HStack {
                    TextField("eventX", text: $model.settings.eventDevice)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        model.detectTouchDevice()
                    } label: {
                        Label(L("自动检测"), systemImage: "scope")
                    }
                    .disabled(model.isWorking)
                }
            }

            Section(L("翻页命令")) {
                HStack {
                    Label(flipCommandStatusText, systemImage: flipCommandStatusImage)
                        .foregroundStyle(flipCommandStatusColor)

                    Spacer()

                    Button {
                        model.checkFlipCommands()
                    } label: {
                        Label(L("检查命令"), systemImage: "checklist")
                    }
                    .disabled(model.isWorking)
                }

                ForEach(FlipCommandDefinition.all) { command in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: command))
                            .foregroundStyle(color(for: command))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(command.title)
                                .font(.body)
                            Text(command.remotePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Button {
                            model.recordFlipCommand(command)
                        } label: {
                            Label(buttonTitle(for: command), systemImage: "record.circle")
                        }
                        .disabled(model.isWorking)
                    }
                    .padding(.vertical, 4)
                }

                Text(L("录制时会清空该指令旧文件，并在 5 秒内等待你在 Kindle 上执行对应手势。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("同步诊断")) {
                LabeledContent(L("摘抄缓存")) {
                    Text(model.clippingsCacheURL?.lastPathComponent ?? L("暂无缓存"))
                        .foregroundStyle(model.clippingsCacheURL == nil ? .secondary : .primary)
                }

                if let path = model.clippingsCachePath {
                    LabeledContent(L("路径")) {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                LabeledContent(L("最后修改")) {
                    Text(lastClippingsSyncText)
                        .foregroundStyle(model.clippingsLastSyncDate == nil ? .secondary : .primary)
                }

                LabeledContent(L("当前解析")) {
                    Text(LF("%d 条 / %d 本书", model.clippings.count, model.clippingBookCount))
                        .monospacedDigit()
                }

                if !clippingsFilterText.isEmpty {
                    LabeledContent(L("已过滤")) {
                        Text(clippingsFilterText)
                            .monospacedDigit()
                    }
                }

                HStack {
                    Button {
                        model.reloadCachedClippings()
                    } label: {
                        Label(L("重新解析缓存"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isWorking)

                    Button {
                        model.openClippingsCacheFile()
                    } label: {
                        Label(L("打开缓存文件"), systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(model.clippingsCachePath == nil)
                }

                Text(L("重新解析只读取本地缓存，不会连接 Kindle。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        model.saveSettings()
                    } label: {
                        Label(L("保存"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.testConnection()
                    } label: {
                        Label(L("测试连接"), systemImage: "checkmark.circle")
                    }
                    .disabled(model.isWorking)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var lastClippingsSyncText: String {
        guard let date = model.clippingsLastSyncDate else {
            return L("暂无记录")
        }
        return diagnosticDateFormatter.string(from: date)
    }

    private var clippingsFilterText: String {
        [
            model.filteredSingleSelectionCount > 0
                ? LF("单字/单词 %d 条", model.filteredSingleSelectionCount)
                : nil,
            model.filteredDuplicateClippingCount > 0
                ? LF("重复摘抄 %d 条", model.filteredDuplicateClippingCount)
                : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var diagnosticDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = languageStore.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var flipCommandStatusText: String {
        guard model.hasCheckedFlipCommands else {
            return L("尚未检查")
        }
        if model.missingFlipCommands.isEmpty {
            return L("4 个翻页命令都已就绪")
        }
        return LF("缺少 %d 个翻页命令", model.missingFlipCommands.count)
    }

    private var flipCommandStatusImage: String {
        guard model.hasCheckedFlipCommands else {
            return "questionmark.circle"
        }
        return model.missingFlipCommands.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var flipCommandStatusColor: Color {
        guard model.hasCheckedFlipCommands else {
            return .secondary
        }
        return model.missingFlipCommands.isEmpty ? .green : .orange
    }

    private func isMissing(_ command: FlipCommandDefinition) -> Bool {
        model.hasCheckedFlipCommands && model.missingFlipCommands.contains(command)
    }

    private func icon(for command: FlipCommandDefinition) -> String {
        guard model.hasCheckedFlipCommands else {
            return "questionmark.circle"
        }
        return isMissing(command) ? "exclamationmark.circle" : "checkmark.circle"
    }

    private func color(for command: FlipCommandDefinition) -> Color {
        guard model.hasCheckedFlipCommands else {
            return .secondary
        }
        return isMissing(command) ? .orange : .green
    }

    private func buttonTitle(for command: FlipCommandDefinition) -> String {
        if isMissing(command) || !model.hasCheckedFlipCommands {
            return L("录制")
        }
        return L("重新录制")
    }
}
