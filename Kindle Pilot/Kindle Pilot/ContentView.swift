import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var model = KindlePilotViewModel()
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var selectedSection: AppSection = .clippings
    @State private var isBookUploadPresented = false
    @State private var hoveredToolbarHelp: String?
    @FocusState private var shortcutsFocused: Bool

    var body: some View {
        let _ = languageStore.preference

        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedSection) {
                    Section(L("整理")) {
                        sidebarRow(
                            title: L("摘抄"),
                            systemImage: "doc.text",
                            count: model.clippings.count
                        )
                        .tag(AppSection.clippings)

                        sidebarRow(
                            title: L("生词本"),
                            systemImage: "book.closed",
                            count: model.vocabularyWordCount
                        )
                        .tag(AppSection.vocabulary)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                Button {
                    selectedSection = .settings
                } label: {
                    Label(L("设置"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == .settings
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detailView
                .navigationTitle("")
        }
        .frame(minWidth: 980, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                toolbarHelp(connectionBadgeHelp) {
                    connectionBadge
                }
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarButton(
                    systemImage: syncButtonImage,
                    help: syncButtonHelp,
                    action: syncCurrentSection
                )
                .disabled(model.isWorking)
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarButton(
                    systemImage: "books.vertical",
                    help: L("传书到 Kindle"),
                    action: chooseBooks
                )
                .disabled(model.isWorking)
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarHelp(
                    L("监听键盘方向键翻页"),
                    trailingPadding: model.keyboardPageTurnEnabled ? 0 : 10
                ) {
                    Toggle(isOn: $model.keyboardPageTurnEnabled) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if model.keyboardPageTurnEnabled {
                ToolbarItem(placement: .primaryAction) {
                    toolbarButton(
                        systemImage: "arrow.left",
                        help: L("让 Kindle 翻到上一页")
                    ) {
                        model.turnPage(.previous)
                    }
                    .disabled(model.isWorking)
                }

                ToolbarItem(placement: .primaryAction) {
                    toolbarButton(
                        systemImage: "arrow.right",
                        help: L("让 Kindle 翻到下一页"),
                        trailingPadding: 10
                    ) {
                        model.turnPage(.next)
                    }
                    .disabled(model.isWorking)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($shortcutsFocused)
        .onAppear {
            shortcutsFocused = true
        }
        .task {
            await model.loadCachedDataOnLaunch()
        }
        .onMoveCommand { direction in
            model.handleMoveCommand(direction)
        }
        .sheet(isPresented: $isBookUploadPresented) {
            BookSyncView(model: model)
                .frame(minWidth: 680, minHeight: 520)
        }
        .alert(item: $model.userAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: alert.message.isEmpty ? nil : Text(alert.message),
                dismissButton: .default(Text(L("好")))
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .clippings:
            ClippingsView(model: model, section: .clippings)
        case .vocabulary:
            ClippingsView(model: model, section: .vocabulary)
        case .settings:
            SettingsView(model: model)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 0) {
            Text(model.settings.host.isEmpty ? L("未设置 Kindle") : model.settings.host)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 92, height: 28, alignment: .trailing)
        .contentShape(Rectangle())
    }

    private var syncButtonImage: String {
        selectedSection == .settings ? "checkmark.circle" : "arrow.clockwise"
    }

    private var syncButtonHelp: String {
        switch selectedSection {
        case .clippings:
            return L("同步 Kindle 摘抄")
        case .vocabulary:
            return L("同步 Kindle 生词本")
        case .settings:
            return L("测试 Kindle 连接")
        }
    }

    private var connectionBadgeHelp: String {
        model.settings.host.isEmpty ? L("未设置 Kindle IP") : LF("Kindle IP: %@", model.settings.host)
    }

    private func toolbarHelp<Content: View>(
        _ text: String,
        trailingPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 4)
            .padding(.trailing, trailingPadding)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background {
                if hoveredToolbarHelp == text {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.10))
                }
            }
            .onHover { isHovering in
                updateToolbarHelp(text, isHovering: isHovering)
            }
            .help(text)
            .animation(.easeOut(duration: 0.12), value: hoveredToolbarHelp)
    }

    private func toolbarButton(
        systemImage: String,
        help: String,
        trailingPadding: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        toolbarHelp(help, trailingPadding: trailingPadding) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func updateToolbarHelp(_ text: String, isHovering: Bool) {
        hoveredToolbarHelp = isHovering ? text : nil
    }

    private func sidebarRow(title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func syncCurrentSection() {
        switch selectedSection {
        case .clippings:
            model.syncClippings()
        case .vocabulary:
            model.syncVocabulary()
        case .settings:
            model.testConnection()
        }
    }

    private func chooseBooks() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = BookSyncService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.begin { response in
            guard response == .OK else { return }
            isBookUploadPresented = true
            model.uploadBooks(panel.urls)
        }
        #endif
    }
}

private enum AppSection: Hashable {
    case clippings
    case vocabulary
    case settings
}
