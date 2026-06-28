import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: KindlePilotViewModel
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        let _ = languageStore.preference

        HStack(alignment: .top, spacing: 16) {
            statusPanel
            controlsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.statusText, systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            LabeledContent("Kindle") {
                Text(model.settings.host.isEmpty ? "-" : model.settings.host)
                    .foregroundStyle(.secondary)
            }

            LabeledContent(L("用户名")) {
                Text(model.settings.username.isEmpty ? "-" : model.settings.username)
                    .foregroundStyle(.secondary)
            }

            LabeledContent(L("触控设备")) {
                Text(model.settings.normalizedEventDevice.map { "/dev/input/\($0)" } ?? "-")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    model.testConnection()
                } label: {
                    Label(L("测试连接"), systemImage: "checkmark.circle")
                }

                Button {
                    model.detectTouchDevice()
                } label: {
                    Label(L("自动检测"), systemImage: "scope")
                }
            }
            .disabled(model.isWorking)

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    model.turnPage(.previous)
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 30, weight: .semibold))
                        Text(L("上一页"))
                            .font(.title3.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.turnPage(.next)
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 30, weight: .semibold))
                        Text(L("下一页"))
                            .font(.title3.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(model.isWorking)

            HStack(spacing: 12) {
                Button {
                    model.testConnection()
                } label: {
                    Label(L("连接"), systemImage: "bolt.horizontal")
                }

                Button {
                    model.detectTouchDevice()
                } label: {
                    Label(L("检测 event"), systemImage: "dot.radiowaves.left.and.right")
                }

                Button {
                    model.checkFlipCommands()
                } label: {
                    Label(L("检查命令"), systemImage: "checklist")
                }
            }
            .disabled(model.isWorking)

            flipCommandPanel

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var flipCommandPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("翻页命令"), systemImage: "record.circle")
                    .font(.headline)
                Spacer()
                Button {
                    model.checkFlipCommands()
                } label: {
                    Label(L("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isWorking)
            }

            if !model.hasCheckedFlipCommands {
                Text(L("点击检查后会确认 Kindle 上是否已有 4 个 FlipCmd 事件文件。"))
                    .foregroundStyle(.secondary)
            } else if model.missingFlipCommands.isEmpty {
                Label(L("4 个翻页命令都已就绪"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                Text(L("点击录制后，5 秒内在 Kindle 上执行对应手势。"))
                    .foregroundStyle(.secondary)

                ForEach(model.missingFlipCommands) { command in
                    HStack {
                        Text(command.title)
                        Spacer()
                        Button {
                            model.recordFlipCommand(command)
                        } label: {
                            Label(L("录制"), systemImage: "record.circle")
                        }
                        .disabled(model.isWorking)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
