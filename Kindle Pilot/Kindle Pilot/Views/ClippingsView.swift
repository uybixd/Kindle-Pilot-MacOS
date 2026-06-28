import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ClippingsView: View {
    @ObservedObject var model: KindlePilotViewModel
    @EnvironmentObject private var languageStore: AppLanguageStore
    let section: ClippingsSection

    var body: some View {
        let _ = languageStore.preference

        VStack(alignment: .leading, spacing: 14) {
            header

            switch section {
            case .clippings:
                clippingsContent
            case .vocabulary:
                vocabularyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .onChange(of: model.clippingSearchText) {
            model.refreshClippingSelection()
        }
        .onChange(of: model.filteredClippings.count) {
            model.refreshClippingSelection()
        }
        .onChange(of: model.vocabularySearchText) {
            model.refreshVocabularySelection()
        }
        .onChange(of: model.vocabularyWordSummaries.count) {
            model.refreshVocabularySelection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(section.title, systemImage: section.systemImage)
                .font(.title2.weight(.semibold))

            Text(headerCountText)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let lastSync = headerLastSyncDate {
                Text(lastSyncFormatter.string(from: lastSync))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            TextField(L("搜索"), text: searchBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Menu {
                Button {
                    syncCurrentSection()
                } label: {
                    Label(section == .clippings ? L("从 Kindle 同步") : L("从 Kindle 同步生词本"), systemImage: "arrow.clockwise")
                }

                Button {
                    importCurrentSection()
                } label: {
                    Label(section == .clippings ? L("导入 My Clippings.txt") : L("导入 vocab.db"), systemImage: "square.and.arrow.down")
                }
            } label: {
                Label(L("获取"), systemImage: "tray.and.arrow.down")
            }
            .disabled(model.isWorking)

            if section == .clippings {
                Menu {
                    Button {
                        export(.markdown)
                    } label: {
                        Label("Markdown", systemImage: "doc.plaintext")
                    }

                    Button {
                        export(.csv)
                    } label: {
                        Label("CSV", systemImage: "tablecells")
                    }

                    Button {
                        export(.plainText)
                    } label: {
                        Label("TXT", systemImage: "doc.text")
                    }
                } label: {
                    Label(L("导出"), systemImage: "square.and.arrow.up")
                }
                .disabled(model.filteredClippings.isEmpty)
            } else {
                Button {
                    exportVocabulary()
                } label: {
                    Label(L("导出 TXT"), systemImage: "square.and.arrow.up")
                }
                .disabled(model.filteredVocabularyLookups.isEmpty)
            }
        }
    }

    private var clippingsContent: some View {
        Group {
            if model.clippings.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    bookSidebar
                        .frame(width: 260)

                    Divider()

                    clippingList
                        .frame(minWidth: 300)

                    Divider()

                    clippingDetail
                        .frame(minWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(L("暂无摘抄"))
                .font(.title3.weight(.semibold))

            Button {
                model.syncClippings()
            } label: {
                Label(L("同步"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)

            Button {
                importClippings()
            } label: {
                Label(L("导入 My Clippings.txt"), systemImage: "square.and.arrow.down")
            }
            .disabled(model.isWorking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var vocabularyContent: some View {
        Group {
            if model.vocabularyLookups.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text(L("暂无生词"))
                        .font(.title3.weight(.semibold))

                    Button {
                        model.syncVocabulary()
                    } label: {
                        Label(L("同步生词本"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)

                    Button {
                        importVocabulary()
                    } label: {
                        Label(L("导入 vocab.db"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isWorking)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    vocabularySidebar
                        .frame(width: 300)

                    Divider()

                    vocabularyDetail
                        .frame(minWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var vocabularySidebar: some View {
        let summaries = model.vocabularyWordSummaries
        let selectedID = model.selectedVocabularyWordID ?? summaries.first?.id

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(summaries) { summary in
                    SelectableRow(isSelected: selectedID == summary.id) {
                        model.selectVocabularyWord(summary.id)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(summary.displayTitle)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    if summary.isFocus {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                Text(LF("%d 次", summary.lookupCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 10)
        }
    }

    private var vocabularyDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = model.selectedVocabularyWordSummary {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.displayTitle)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        if summary.isFocus {
                            Label(L("重点"), systemImage: "star.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }

                    HStack(spacing: 14) {
                        Text(LF("%d 条查词记录", summary.lookupCount))
                        if model.filteredChineseVocabularyLookupCount > 0 {
                            Text(LF("已过滤中文 %d 条", model.filteredChineseVocabularyLookupCount))
                        }
                        if model.vocabularyFocusCandidateCount > 0 {
                            Text(LF("重点候选 %d", model.vocabularyFocusCandidateCount))
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Divider()
                }

                ForEach(model.selectedVocabularyLookups) { lookup in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(lookup.bookDisplayTitle)
                                .font(.headline)
                                .textSelection(.enabled)
                            Spacer()
                            if let position = lookup.position {
                                Text(LF("位置 %@", position))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let lookedUpAt = lookup.lookedUpAt {
                            Text(vocabularyDateFormatter.string(from: lookedUpAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !lookup.usage.isEmpty {
                            Text(lookup.usage)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)

                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
        }
    }

    private var bookSidebar: some View {
        let selectedBookID = model.selectedClippingBookID

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                bookRow(
                    title: L("全部"),
                    subtitle: "\(model.clippings.count)",
                    isSelected: selectedBookID == nil
                ) {
                    model.selectClippingBook(nil)
                }

                ForEach(model.clippingBookSummaries) { summary in
                    bookRow(
                        title: summary.displayTitle,
                        subtitle: "\(summary.count)",
                        isSelected: selectedBookID == summary.id
                    ) {
                        model.selectClippingBook(summary.id)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 10)
        }
    }

    private func bookRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SelectableRow(isSelected: isSelected, action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var clippingList: some View {
        let clippings = model.filteredClippings
        let selectedID = model.selectedClippingID ?? clippings.first?.id

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(clippings) { clipping in
                    SelectableRow(isSelected: selectedID == clipping.id) {
                        model.selectedClippingID = clipping.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(clipping.kind.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(kindColor(clipping.kind))
                                if !clipping.kindleNotes.isEmpty {
                                    Label("\(clipping.kindleNotes.count)", systemImage: "note.text")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                                if !clipping.referenceText.isEmpty {
                                    Text(clipping.referenceText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Text(clipping.text.isEmpty ? clipping.metadata : clipping.text)
                                .lineLimit(3)
                                .font(.callout)

                            Text(clipping.bookDisplayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var clippingDetail: some View {
        ScrollView {
            if let clipping = model.selectedClipping {
                VStack(alignment: .leading, spacing: 14) {
                    Text(clipping.bookDisplayTitle)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Label(clipping.kind.title, systemImage: icon(for: clipping.kind))
                            .foregroundStyle(kindColor(clipping.kind))

                        if !clipping.referenceText.isEmpty {
                            Text(clipping.referenceText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)

                    if let addedAt = clipping.addedAt {
                        Text(detailDateFormatter.string(from: addedAt))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    if clipping.kind == .note {
                        noteBlock(
                            title: L("Kindle 批注"),
                            text: clipping.text,
                            metadata: clipping.metadata,
                            addedAt: clipping.addedAt
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(clipping.text.isEmpty ? L("_无内容_") : clipping.text)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }

                        ForEach(clipping.kindleNotes) { note in
                            Divider()
                            noteBlock(
                                title: L("Kindle 批注"),
                                text: note.text,
                                metadata: note.metadata,
                                addedAt: note.addedAt
                            )
                        }
                    }

                    Divider()

                    Text(clipping.metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(L("未选择摘抄"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            }
        }
    }

    private func noteBlock(
        title: String,
        text: String,
        metadata: String,
        addedAt: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(.blue)

            Text(text.isEmpty ? L("_无内容_") : text)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)

            if let addedAt {
                Text(detailDateFormatter.string(from: addedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func export(_ format: ClippingsExportFormat) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultClippingsExportFileName(for: format)
        panel.allowedContentTypes = UTType(filenameExtension: format.fileExtension).map { [$0] } ?? []
        let includeDetailsButton = NSButton(
            checkboxWithTitle: L("包含时间、位置等信息"),
            target: nil,
            action: nil
        )
        includeDetailsButton.state = .on
        panel.accessoryView = includeDetailsButton

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let options = ClippingsExportOptions(
                includeDetails: includeDetailsButton.state == .on
            )
            model.exportVisibleClippings(format: format, options: options, to: url)
        }
        #endif
    }

    private func defaultClippingsExportFileName(for format: ClippingsExportFormat) -> String {
        let baseName: String
        if let selectedBookID = model.selectedClippingBookID,
           let summary = model.clippingBookSummaries.first(where: { $0.id == selectedBookID }) {
            baseName = "\(summary.title)_Clippings"
        } else {
            baseName = "Kindle_Clippings"
        }

        return "\(sanitizedFileName(baseName)).\(format.fileExtension)"
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Kindle_Clippings" : sanitized
    }

    private func exportVocabulary() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Kindle-Vocabulary.txt"
        panel.allowedContentTypes = UTType(filenameExtension: "txt").map { [$0] } ?? []
        let includeDetailsButton = NSButton(
            checkboxWithTitle: L("包含书籍、位置、例句"),
            target: nil,
            action: nil
        )
        includeDetailsButton.state = .on
        panel.accessoryView = includeDetailsButton

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let options = VocabularyExportOptions(
                includeDetails: includeDetailsButton.state == .on
            )
            model.exportVisibleVocabulary(options: options, to: url)
        }
        #endif
    }

    private func syncCurrentSection() {
        switch section {
        case .clippings:
            model.syncClippings()
        case .vocabulary:
            model.syncVocabulary()
        }
    }

    private func importCurrentSection() {
        switch section {
        case .clippings:
            importClippings()
        case .vocabulary:
            importVocabulary()
        }
    }

    private func importClippings() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text]
        panel.prompt = L("导入")
        panel.message = L("选择从 Kindle 复制出来的 My Clippings.txt")

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.importLocalClippings(from: url)
        }
        #endif
    }

    private func importVocabulary() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = UTType(filenameExtension: "db").map { [$0] } ?? []
        panel.prompt = L("导入")
        panel.message = L("选择从 Kindle 复制出来的 system/vocabulary/vocab.db")

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.importLocalVocabulary(from: url)
        }
        #endif
    }

    private var headerCountText: String {
        switch section {
        case .clippings:
            return "\(model.filteredClippings.count) / \(model.clippings.count)"
        case .vocabulary:
            return "\(model.vocabularyWordSummaries.count) / \(model.filteredVocabularyLookups.count)"
        }
    }

    private var headerLastSyncDate: Date? {
        switch section {
        case .clippings:
            return model.clippingsLastSyncDate
        case .vocabulary:
            return model.vocabularyLastSyncDate
        }
    }

    private var searchBinding: Binding<String> {
        switch section {
        case .clippings:
            return $model.clippingSearchText
        case .vocabulary:
            return $model.vocabularySearchText
        }
    }

    private func kindColor(_ kind: ClippingKind) -> Color {
        switch kind {
        case .highlight:
            return .yellow
        case .note:
            return .blue
        case .bookmark:
            return .green
        case .unknown:
            return .secondary
        }
    }

    private func icon(for kind: ClippingKind) -> String {
        switch kind {
        case .highlight:
            return "highlighter"
        case .note:
            return "note.text"
        case .bookmark:
            return "bookmark"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var lastSyncFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = languageStore.locale
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }

    private var detailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = languageStore.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private var vocabularyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = languageStore.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

enum ClippingsSection: Hashable {
    case clippings
    case vocabulary

    var title: String {
        switch self {
        case .clippings:
            return L("摘抄整理")
        case .vocabulary:
            return L("生词本")
        }
    }

    var systemImage: String {
        switch self {
        case .clippings:
            return "doc.text"
        case .vocabulary:
            return "book.closed"
        }
    }
}

private struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: () -> Content

    @State private var isHovered = false

    init(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.action = action
        self.content = label
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}
