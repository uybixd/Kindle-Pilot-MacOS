import Combine
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct UserAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum DuplicateUploadDecision {
    case skipDuplicates
    case uploadDuplicates
    case cancel
}

enum BookUploadStatus {
    case checking
    case pending
    case uploading
    case uploaded
    case skipped
    case failed

    var title: String {
        switch self {
        case .checking:
            return L("检查中")
        case .pending:
            return L("等待")
        case .uploading:
            return L("上传中")
        case .uploaded:
            return L("完成")
        case .skipped:
            return L("已跳过")
        case .failed:
            return L("失败")
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "magnifyingglass.circle"
        case .pending:
            return "clock"
        case .uploading:
            return "arrow.up.circle"
        case .uploaded:
            return "checkmark.circle"
        case .skipped:
            return "minus.circle"
        case .failed:
            return "xmark.circle"
        }
    }
}

struct BookUploadItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: BookUploadStatus = .pending
    var remotePath: String?
    var errorMessage: String?
    var bytesSent: Int64 = 0
    var totalBytes: Int64 = 0

    var fileName: String {
        url.lastPathComponent
    }

    var progressFraction: Double {
        guard totalBytes > 0 else {
            return status == .uploaded ? 1 : 0
        }
        let boundedBytes = min(max(bytesSent, 0), totalBytes)
        return Double(boundedBytes) / Double(totalBytes)
    }
}

@MainActor
final class KindlePilotViewModel: ObservableObject {
    @Published var settings: ConnectionSettings
    @Published var password: String
    @Published var userAlert: UserAlert?
    @Published var isWorking = false
    @Published var statusText = L("未连接")
    @Published var keyboardPageTurnEnabled = false
    @Published var hasCheckedFlipCommands = false
    @Published var missingFlipCommands: [FlipCommandDefinition] = []
    @Published var uploadItems: [BookUploadItem] = []
    @Published var clippings: [Clipping] = []
    @Published var clippingSearchText = ""
    @Published var selectedClippingBookID: String?
    @Published var selectedClippingID: Clipping.ID?
    @Published var clippingsCacheURL: URL?
    @Published var clippingsLastSyncDate: Date?
    @Published var filteredSingleSelectionCount = 0
    @Published var filteredDuplicateClippingCount = 0
    @Published var vocabularyLookups: [VocabularyLookup] = []
    @Published var vocabularySearchText = ""
    @Published var selectedVocabularyWordID: VocabularyWordSummary.ID?
    @Published var vocabularyCacheURL: URL?
    @Published var vocabularyLastSyncDate: Date?
    @Published var filteredChineseVocabularyLookupCount = 0
    @Published var filteredChineseVocabularyWordCount = 0
    @Published var vocabularyFocusCandidateCount = 0
    @Published var unmatchedVocabularyFocusCandidateCount = 0

    private let passwordAccount = "kindle-ssh-password"
    private let settingsStore: AppSettingsStore
    private let keychainStore: KeychainStore
    private let connectionService: ConnectionService
    private let remoteControlService: RemoteControlService
    private let bookSyncService: BookSyncService
    private let clippingsService: ClippingsService
    private let vocabularyService: VocabularyService
    private var vocabularyFocusCandidates = Set<String>()
    private var didLoadCachedDataOnLaunch = false

    init() {
        self.settingsStore = AppSettingsStore()
        self.keychainStore = KeychainStore()
        self.settings = Self.passwordOnly(settingsStore.load())
        self.password = (try? keychainStore.loadPassword(account: passwordAccount)) ?? ""

        let connectionService = ConnectionService(
            keychainStore: keychainStore,
            passwordAccount: passwordAccount
        )
        self.connectionService = connectionService
        self.remoteControlService = RemoteControlService(connectionService: connectionService)
        self.bookSyncService = BookSyncService(connectionService: connectionService)
        self.clippingsService = ClippingsService(connectionService: connectionService)
        self.vocabularyService = VocabularyService(connectionService: connectionService)
    }

    init(settingsStore: AppSettingsStore, keychainStore: KeychainStore) {
        self.settingsStore = settingsStore
        self.keychainStore = keychainStore
        self.settings = Self.passwordOnly(settingsStore.load())
        self.password = (try? keychainStore.loadPassword(account: passwordAccount)) ?? ""

        let connectionService = ConnectionService(
            keychainStore: keychainStore,
            passwordAccount: passwordAccount
        )
        self.connectionService = connectionService
        self.remoteControlService = RemoteControlService(connectionService: connectionService)
        self.bookSyncService = BookSyncService(connectionService: connectionService)
        self.clippingsService = ClippingsService(connectionService: connectionService)
        self.vocabularyService = VocabularyService(connectionService: connectionService)
    }

    var clippingBookSummaries: [ClippingBookSummary] {
        Dictionary(grouping: clippings, by: \.bookID)
            .compactMap { bookID, clippings in
                guard let first = clippings.first else { return nil }
                return ClippingBookSummary(
                    id: bookID,
                    title: first.bookTitle,
                    author: first.author,
                    count: clippings.count
                )
            }
            .sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
    }

    var filteredClippings: [Clipping] {
        let scoped = selectedClippingBookID.map { bookID in
            clippings.filter { $0.bookID == bookID }
        } ?? clippings

        let query = clippingSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return scoped
        }

        return scoped.filter { clipping in
            let values = [
                clipping.bookTitle,
                clipping.author ?? "",
                clipping.text,
                clipping.metadata,
                clipping.referenceText
            ] + clipping.kindleNotes.flatMap { note in
                [note.text, note.metadata, note.referenceText]
            }

            return values.contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var selectedClipping: Clipping? {
        let visible = filteredClippings
        guard let selectedClippingID else {
            return visible.first
        }
        return visible.first { $0.id == selectedClippingID } ?? visible.first
    }

    var filteredVocabularyLookups: [VocabularyLookup] {
        let query = vocabularySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return vocabularyLookups
        }

        return vocabularyLookups.filter { lookup in
            [
                lookup.word,
                lookup.stem,
                lookup.bookTitle,
                lookup.authors,
                lookup.usage
            ].contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var vocabularyWordSummaries: [VocabularyWordSummary] {
        Dictionary(grouping: filteredVocabularyLookups, by: \.wordKey)
            .compactMap { wordKey, lookups in
                guard let first = lookups.first else { return nil }
                return VocabularyWordSummary(
                    id: wordKey,
                    word: first.word,
                    stem: first.stem,
                    lookupCount: lookups.count,
                    isFocus: lookups.contains { $0.isFocus }
                )
            }
            .sorted {
                if $0.isFocus != $1.isFocus {
                    return $0.isFocus && !$1.isFocus
                }
                return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
    }

    var selectedVocabularyLookups: [VocabularyLookup] {
        let summaries = vocabularyWordSummaries
        let selectedID = selectedVocabularyWordID ?? summaries.first?.id
        guard let selectedID else {
            return []
        }
        return filteredVocabularyLookups
            .filter { $0.wordKey == selectedID }
            .sorted {
                let leftTime = $0.timestamp ?? 0
                let rightTime = $1.timestamp ?? 0
                if leftTime != rightTime {
                    return leftTime < rightTime
                }
                return ($0.position ?? "") < ($1.position ?? "")
            }
    }

    var selectedVocabularyWordSummary: VocabularyWordSummary? {
        let summaries = vocabularyWordSummaries
        guard let selectedVocabularyWordID else {
            return summaries.first
        }
        return summaries.first { $0.id == selectedVocabularyWordID } ?? summaries.first
    }

    var vocabularyWordCount: Int {
        Set(vocabularyLookups.map(\.wordKey)).count
    }

    var clippingBookCount: Int {
        clippingBookSummaries.count
    }

    var uploadProgressFraction: Double {
        let uploadableItems = uploadItems.filter { $0.status != .skipped }
        let totalBytes = uploadableItems.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard totalBytes > 0 else {
            return uploadItems.isEmpty ? 0 : 1
        }

        let sentBytes = uploadableItems.reduce(Int64(0)) { partialResult, item in
            switch item.status {
            case .uploaded:
                return partialResult + item.totalBytes
            default:
                return partialResult + min(max(item.bytesSent, 0), item.totalBytes)
            }
        }
        return min(max(Double(sentBytes) / Double(totalBytes), 0), 1)
    }

    var uploadProgressSummary: String {
        guard !uploadItems.isEmpty else {
            return ""
        }

        let uploadedCount = uploadItems.filter { $0.status == .uploaded }.count
        let failedCount = uploadItems.filter { $0.status == .failed }.count
        let skippedCount = uploadItems.filter { $0.status == .skipped }.count
        let totalCount = uploadItems.count
        let percent = Int((uploadProgressFraction * 100).rounded())
        var parts = [LF("%d/%d 本", uploadedCount, totalCount), "\(percent)%"]
        if skippedCount > 0 {
            parts.append(LF("跳过 %d", skippedCount))
        }
        if failedCount > 0 {
            parts.append(LF("失败 %d", failedCount))
        }
        return parts.joined(separator: " · ")
    }

    var clippingsCachePath: String? {
        if let clippingsCacheURL {
            return clippingsCacheURL.path
        }
        return try? clippingsService.cachedClippingsURL().path
    }

    func saveSettings() {
        do {
            settings = Self.passwordOnly(settings)
            try settingsStore.save(settings)
            try keychainStore.savePassword(password, account: passwordAccount)
            presentAlert(L("设置已保存"))
        } catch {
            presentAlert(L("保存失败"), message: error.localizedDescription)
        }
    }

    func testConnection() {
        runTask(status: L("正在测试连接")) {
            try self.persistConnectionState()
            let output = try await self.connectionService.testConnection(settings: self.settings)
            self.statusText = L("已连接")
            self.presentAlert(L("连接成功"), message: output)
        }
    }

    func detectTouchDevice() {
        runTask(status: L("正在检测触控设备")) {
            try self.persistConnectionState()
            let event = try await self.connectionService.detectTouchDevice(settings: self.settings)
            self.settings.eventDevice = event
            try self.settingsStore.save(self.settings)
            self.statusText = L("已检测触控设备")
            self.presentAlert(L("检测完成"), message: LF("检测到 /dev/input/%@", event))
        }
    }

    func turnPage(_ direction: PageTurnDirection) {
        runTask(status: LF("%@请求已发送", direction.logTitle)) {
            try self.persistConnectionState()
            let output = try await self.remoteControlService.turnPage(
                settings: self.settings,
                direction: direction
            )
            self.statusText = output.isEmpty ? LF("%@完成", direction.logTitle) : output
        }
    }

    func checkFlipCommands() {
        runTask(status: L("正在检查翻页命令")) {
            try self.persistConnectionState()
            let missing = try await self.remoteControlService.missingFlipCommands(settings: self.settings)
            self.hasCheckedFlipCommands = true
            self.missingFlipCommands = missing

            if missing.isEmpty {
                self.statusText = L("翻页命令已就绪")
                self.presentAlert(L("翻页命令已就绪"))
            } else {
                let names = missing.map(\.title).joined(separator: L("，"))
                self.statusText = L("缺少翻页命令")
                self.presentAlert(L("缺少翻页命令"), message: names)
            }
        }
    }

    func recordFlipCommand(_ definition: FlipCommandDefinition) {
        runTask(status: LF("准备录制%@", definition.title)) {
            try self.persistConnectionState()
            let output = try await self.remoteControlService.recordFlipCommand(
                settings: self.settings,
                definition: definition,
                duration: 5
            )
            self.statusText = LF("%@录制完成", definition.title)
            self.presentAlert(L("录制完成"), message: output)

            let missing = try await self.remoteControlService.missingFlipCommands(settings: self.settings)
            self.hasCheckedFlipCommands = true
            self.missingFlipCommands = missing
        }
    }

    func uploadBooks(_ urls: [URL]) {
        guard !isWorking else { return }

        let supported = urls.filter { BookSyncService.isSupportedBookURL($0) }
        let unsupported = urls.filter { !BookSyncService.isSupportedBookURL($0) }
        let unsupportedNames = unsupported.map(\.lastPathComponent)

        guard !supported.isEmpty else {
            presentAlert(
                L("没有可上传的书籍文件"),
                message: unsupportedNames.isEmpty ? nil : LF("已跳过: %@", unsupportedNames.joined(separator: L("，")))
            )
            return
        }

        let items = supported.map {
            BookUploadItem(
                url: $0,
                status: .checking,
                totalBytes: fileSize(for: $0)
            )
        }
        uploadItems = items
        isWorking = true
        statusText = L("正在检查 Kindle 中已有书籍")

        Task {
            var uploadedCount = 0
            var failedCount = 0
            var skippedCount = 0

            do {
                try self.persistConnectionState()

                var uploadQueue = items
                let duplicates = try await self.bookSyncService.duplicateBooks(
                    settings: self.settings,
                    localURLs: supported
                )

                if !duplicates.isEmpty {
                    let duplicateIDs = Set(
                        duplicates.compactMap { match in
                            items.first { $0.url == match.localURL }?.id
                        }
                    )

                    switch self.confirmDuplicateUpload(duplicates) {
                    case .skipDuplicates:
                        skippedCount = duplicateIDs.count
                        uploadQueue = items.filter { !duplicateIDs.contains($0.id) }
                        for match in duplicates {
                            guard let item = items.first(where: { $0.url == match.localURL }) else {
                                continue
                            }
                            self.updateUploadItem(
                                item.id,
                                status: .skipped,
                                errorMessage: self.duplicateSkipMessage(for: match)
                            )
                        }
                    case .uploadDuplicates:
                        uploadQueue = items
                    case .cancel:
                        for item in items {
                            self.updateUploadItem(
                                item.id,
                                status: .skipped,
                                errorMessage: L("用户取消上传")
                            )
                        }
                        self.statusText = L("传书已取消")
                        self.presentAlert(L("传书已取消"))
                        self.isWorking = false
                        return
                    }
                }

                for item in uploadQueue {
                    self.updateUploadItem(item.id, status: .pending)
                }

                self.statusText = uploadQueue.isEmpty
                    ? L("没有需要上传的书籍")
                    : LF("正在上传 %d 本书", uploadQueue.count)

                for (index, item) in uploadQueue.enumerated() {
                    self.updateUploadItem(item.id, status: .uploading)
                    self.statusText = LF("正在上传 %d/%d: %@", index + 1, uploadQueue.count, item.fileName)
                    let isAccessing = item.url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing {
                            item.url.stopAccessingSecurityScopedResource()
                        }
                    }

                    do {
                        let remotePath = try await self.bookSyncService.uploadBook(
                            settings: self.settings,
                            localURL: item.url,
                            progress: { sentBytes, totalBytes in
                                Task { @MainActor in
                                    self.updateUploadProgress(
                                        item.id,
                                        bytesSent: sentBytes,
                                        totalBytes: totalBytes
                                    )
                                }
                            }
                        )
                        let finalBytes = self.uploadItems.first(where: { $0.id == item.id })?.totalBytes ?? item.totalBytes
                        self.updateUploadItem(
                            item.id,
                            status: .uploaded,
                            remotePath: remotePath,
                            bytesSent: finalBytes,
                            totalBytes: finalBytes
                        )
                        uploadedCount += 1
                    } catch {
                        self.updateUploadItem(
                            item.id,
                            status: .failed,
                            errorMessage: error.localizedDescription
                        )
                        failedCount += 1
                    }
                }

                self.statusText = failedCount == 0 ? L("传书完成") : L("传书部分失败")
                var message = LF("成功 %d 本，跳过 %d 本，失败 %d 本", uploadedCount, skippedCount, failedCount)
                if !unsupportedNames.isEmpty {
                    message += "\n" + LF("已跳过: %@", unsupportedNames.joined(separator: L("，")))
                }
                self.presentAlert(failedCount == 0 ? L("传书完成") : L("传书部分失败"), message: message)
            } catch {
                self.markUnfinishedUploadsFailed(error.localizedDescription)
                self.statusText = L("传书失败")
                self.presentAlert(L("传书失败"), message: error.localizedDescription)
            }

            self.isWorking = false
        }
    }

    func syncClippings() {
        runTask(status: L("正在同步摘抄")) {
            try self.persistConnectionState()
            let result = try await self.clippingsService.syncClippings(settings: self.settings)
            self.applyClippingsResult(result)
            self.loadCachedVocabulary()
            let filteredText = self.clippingFilterSummaryText(result)
            self.statusText = L("摘抄同步完成")
            self.presentAlert(L("摘抄同步完成"), message: LF("%d 条%@", result.clippings.count, filteredText))
        }
    }

    func importLocalClippings(from url: URL) {
        guard !isWorking else { return }

        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let result = try clippingsService.importClippings(from: url)
            applyClippingsResult(result)
            loadCachedVocabulary()
            let filteredText = clippingFilterSummaryText(result)
            statusText = L("摘抄导入完成")
            presentAlert(
                L("摘抄导入完成"),
                message: LF("%d 条，%d 本书%@", result.clippings.count, clippingBookCount, filteredText)
            )
        } catch {
            statusText = L("摘抄导入失败")
            presentAlert(L("摘抄导入失败"), message: error.localizedDescription)
        }
    }

    func reloadCachedClippings() {
        guard !isWorking else { return }

        do {
            guard let result = try clippingsService.loadCachedClippings() else {
                presentAlert(L("没有找到摘抄缓存"))
                return
            }

            applyClippingsResult(result)
            loadCachedVocabulary()

            let filteredText = clippingFilterSummaryText(result)
            presentAlert(
                L("摘抄缓存已重新解析"),
                message: LF("%d 条，%d 本书%@", result.clippings.count, clippingBookCount, filteredText)
            )
        } catch {
            presentAlert(L("重新解析摘抄缓存失败"), message: error.localizedDescription)
        }
    }

    func openClippingsCacheFile() {
        let url: URL
        if let clippingsCacheURL {
            url = clippingsCacheURL
        } else {
            do {
                url = try clippingsService.cachedClippingsURL()
            } catch {
                presentAlert(L("无法定位摘抄缓存"), message: error.localizedDescription)
                return
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            presentAlert(L("摘抄缓存不存在"), message: url.path)
            return
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        presentAlert(L("当前平台不支持直接打开缓存文件"), message: url.path)
        #endif
    }

    func syncVocabulary() {
        runTask(status: L("正在同步生词本")) {
            try self.persistConnectionState()
            let result = try await self.vocabularyService.syncVocabulary(
                settings: self.settings,
                focusCandidates: self.vocabularyFocusCandidates
            )
            self.applyVocabularyResult(result)
            self.statusText = L("生词本同步完成")
            self.presentAlert(
                L("生词本同步完成"),
                message: LF("%d 个词，%d 条查词记录", self.uniqueVocabularyWordCount, result.lookups.count)
            )
        }
    }

    func importLocalVocabulary(from url: URL) {
        guard !isWorking else { return }

        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let result = try vocabularyService.importVocabulary(
                from: url,
                focusCandidates: vocabularyFocusCandidates
            )
            applyVocabularyResult(result)
            statusText = L("生词本导入完成")
            presentAlert(
                L("生词本导入完成"),
                message: LF("%d 个词，%d 条查词记录", uniqueVocabularyWordCount, result.lookups.count)
            )
        } catch {
            statusText = L("生词本导入失败")
            presentAlert(L("生词本导入失败"), message: error.localizedDescription)
        }
    }

    func loadCachedDataOnLaunch() async {
        guard !didLoadCachedDataOnLaunch else {
            return
        }

        didLoadCachedDataOnLaunch = true
        await Task.yield()
        loadCachedClippings()
        loadCachedVocabulary()
    }

    func selectClippingBook(_ bookID: String?) {
        selectedClippingBookID = bookID
        refreshClippingSelection()
    }

    func refreshClippingSelection() {
        let visible = filteredClippings
        if let selectedClippingID, visible.contains(where: { $0.id == selectedClippingID }) {
            return
        }
        selectedClippingID = visible.first?.id
    }

    func selectVocabularyWord(_ wordID: VocabularyWordSummary.ID?) {
        selectedVocabularyWordID = wordID
    }

    func refreshVocabularySelection() {
        let visible = vocabularyWordSummaries
        if let selectedVocabularyWordID, visible.contains(where: { $0.id == selectedVocabularyWordID }) {
            return
        }
        selectedVocabularyWordID = visible.first?.id
    }

    func exportVisibleClippings(
        format: ClippingsExportFormat,
        options: ClippingsExportOptions,
        to url: URL
    ) {
        let items = filteredClippings
        guard !items.isEmpty else {
            presentAlert(L("没有可导出的摘抄"))
            return
        }

        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try clippingsService.export(items, format: format, options: options, to: url)
            presentAlert(L("导出完成"), message: LF("已导出 %d 条摘抄: %@", items.count, url.lastPathComponent))
        } catch {
            presentAlert(L("导出失败"), message: error.localizedDescription)
        }
    }

    func exportVisibleVocabulary(options: VocabularyExportOptions, to url: URL) {
        let items = filteredVocabularyLookups
        guard !items.isEmpty else {
            presentAlert(L("没有可导出的生词"))
            return
        }

        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try vocabularyService.export(items, options: options, to: url)
            presentAlert(L("导出完成"), message: LF("已导出 %d 个生词: %@", Set(items.map(\.wordKey)).count, url.lastPathComponent))
        } catch {
            presentAlert(L("导出生词本失败"), message: error.localizedDescription)
        }
    }

    func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard keyboardPageTurnEnabled, !isWorking else { return }

        switch direction {
        case .left, .up:
            turnPage(.previous)
        case .right, .down:
            turnPage(.next)
        @unknown default:
            break
        }
    }

    private func runTask(status: String, operation: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        statusText = status

        Task {
            do {
                try await operation()
            } catch {
                statusText = L("出错")
                presentAlert(L("操作失败"), message: error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func persistConnectionState() throws {
        settings = Self.passwordOnly(settings)
        try settingsStore.save(settings)
        try keychainStore.savePassword(password, account: passwordAccount)
    }

    private static func passwordOnly(_ settings: ConnectionSettings) -> ConnectionSettings {
        var settings = settings
        settings.authenticationMethod = .password
        settings.privateKeyPath = ""
        return settings
    }

    private func presentAlert(_ title: String, message: String? = nil) {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        userAlert = UserAlert(
            title: title,
            message: trimmedMessage?.isEmpty == false ? trimmedMessage ?? "" : ""
        )
    }

    private func loadCachedClippings() {
        do {
            guard let result = try clippingsService.loadCachedClippings() else {
                return
            }
            applyClippingsResult(result)
        } catch {
            presentAlert(L("读取摘抄缓存失败"), message: error.localizedDescription)
        }
    }

    private func loadCachedVocabulary() {
        do {
            guard let result = try vocabularyService.loadCachedVocabulary(
                focusCandidates: vocabularyFocusCandidates
            ) else {
                return
            }
            applyVocabularyResult(result)
        } catch {
            presentAlert(L("读取生词本缓存失败"), message: error.localizedDescription)
        }
    }

    private func applyClippingsResult(_ result: ClippingsSyncResult) {
        clippings = result.clippings
        clippingsCacheURL = result.cacheURL
        clippingsLastSyncDate = result.sourceModifiedAt
        vocabularyFocusCandidates = result.vocabularyFocusCandidates
        filteredSingleSelectionCount = result.filteredSingleSelectionCount
        filteredDuplicateClippingCount = result.filteredDuplicateCount

        if let selectedClippingBookID,
           !clippings.contains(where: { $0.bookID == selectedClippingBookID }) {
            self.selectedClippingBookID = nil
        }
        refreshClippingSelection()
    }

    private func clippingFilterSummaryText(_ result: ClippingsSyncResult) -> String {
        let filters = [
            result.filteredSingleSelectionCount > 0
                ? LF("单字/单词 %d 条", result.filteredSingleSelectionCount)
                : nil,
            result.filteredDuplicateCount > 0
                ? LF("重复摘抄 %d 条", result.filteredDuplicateCount)
                : nil
        ].compactMap { $0 }

        guard !filters.isEmpty else {
            return ""
        }
        return LF("，已过滤%@", filters.joined(separator: L("，")))
    }

    private func applyVocabularyResult(_ result: VocabularySyncResult) {
        vocabularyLookups = result.lookups
        vocabularyCacheURL = result.cacheURL
        vocabularyLastSyncDate = result.sourceModifiedAt
        filteredChineseVocabularyWordCount = result.filteredChineseWordCount
        filteredChineseVocabularyLookupCount = result.filteredChineseLookupCount
        vocabularyFocusCandidateCount = result.focusCandidateCount
        unmatchedVocabularyFocusCandidateCount = result.unmatchedFocusCandidateCount
        refreshVocabularySelection()
    }

    private var uniqueVocabularyWordCount: Int {
        Set(vocabularyLookups.map(\.wordKey)).count
    }

    private func fileSize(for url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func confirmDuplicateUpload(_ duplicates: [KindleBookDuplicateMatch]) -> DuplicateUploadDecision {
        #if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Kindle 中已有同名书籍")
        alert.informativeText = duplicateConfirmationMessage(for: duplicates)
        alert.addButton(withTitle: L("跳过已有"))
        alert.addButton(withTitle: L("仍然上传"))
        alert.addButton(withTitle: L("取消"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .skipDuplicates
        case .alertSecondButtonReturn:
            return .uploadDuplicates
        default:
            return .cancel
        }
        #else
        return .cancel
        #endif
    }

    private func duplicateConfirmationMessage(for duplicates: [KindleBookDuplicateMatch]) -> String {
        let previewLimit = 8
        let preview = duplicates.prefix(previewLimit).map { match in
            let existingPaths = match.existingBooks
                .prefix(3)
                .map(\.remotePath)
                .joined(separator: "\n  ")
            return "- \(match.localTitle)\n  \(existingPaths)"
        }
        .joined(separator: "\n")

        let remainingCount = duplicates.count - previewLimit
        let suffix = remainingCount > 0 ? "\n" + LF("另有 %d 本同名书籍。", remainingCount) : ""
        return LF("将要上传的以下书籍在 Kindle 中已有同名文件。\n请选择跳过，或确认仍然上传。\n\n%@%@", preview, suffix)
    }

    private func duplicateSkipMessage(for match: KindleBookDuplicateMatch) -> String {
        let existingPaths = match.existingBooks
            .prefix(3)
            .map(\.remotePath)
            .joined(separator: L("，"))
        return LF("Kindle 已存在: %@", existingPaths)
    }

    private func markUnfinishedUploadsFailed(_ message: String) {
        let unfinishedIDs = uploadItems
            .filter { item in
                switch item.status {
                case .checking, .pending, .uploading:
                    return true
                case .uploaded, .skipped, .failed:
                    return false
                }
            }
            .map(\.id)

        for id in unfinishedIDs {
            updateUploadItem(id, status: .failed, errorMessage: message)
        }
    }

    private func updateUploadProgress(
        _ id: BookUploadItem.ID,
        bytesSent: Int64,
        totalBytes: Int64
    ) {
        guard let index = uploadItems.firstIndex(where: { $0.id == id }),
              uploadItems[index].status == .uploading else {
            return
        }

        uploadItems[index].bytesSent = bytesSent
        uploadItems[index].totalBytes = totalBytes
    }

    private func updateUploadItem(
        _ id: BookUploadItem.ID,
        status: BookUploadStatus,
        remotePath: String? = nil,
        errorMessage: String? = nil,
        bytesSent: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        guard let index = uploadItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        uploadItems[index].status = status
        if let remotePath {
            uploadItems[index].remotePath = remotePath
        }
        if let errorMessage {
            uploadItems[index].errorMessage = errorMessage
        }
        if let bytesSent {
            uploadItems[index].bytesSent = bytesSent
        }
        if let totalBytes {
            uploadItems[index].totalBytes = totalBytes
        }
    }
}
