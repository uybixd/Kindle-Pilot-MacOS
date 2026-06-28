import Foundation
import SQLite3

final class VocabularyService {
    private let connectionService: ConnectionService

    init(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    func syncVocabulary(
        settings: ConnectionSettings,
        focusCandidates: Set<String>
    ) async throws -> VocabularySyncResult {
        let localURL = try vocabularyCacheURL()
        let client = connectionService.makeClient(settings: settings)
        _ = try await client.download(
            remotePath: "/mnt/us/system/vocabulary/vocab.db",
            to: localURL
        )
        return try loadVocabulary(focusCandidates: focusCandidates)
    }

    func loadCachedVocabulary(focusCandidates: Set<String>) throws -> VocabularySyncResult? {
        let localURL = try vocabularyCacheURL()
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        return try loadVocabulary(focusCandidates: focusCandidates)
    }

    func importVocabulary(
        from sourceURL: URL,
        focusCandidates: Set<String>
    ) throws -> VocabularySyncResult {
        let localURL = try vocabularyCacheURL()
        try copyReplacingItem(from: sourceURL, to: localURL)
        return try loadVocabulary(focusCandidates: focusCandidates)
    }

    func export(
        _ lookups: [VocabularyLookup],
        options: VocabularyExportOptions,
        to url: URL
    ) throws {
        try makePlainText(lookups, options: options).write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadVocabulary(focusCandidates: Set<String>) throws -> VocabularySyncResult {
        let localURL = try vocabularyCacheURL()
        let sourceLookups = try readLookups(from: localURL)
        let filteredLookups = sourceLookups.filter { !isChineseLookup($0) }
        let focusKeys = Set(focusCandidates.compactMap(VocabularyNormalizer.normalizedSingleWord))
        let markedLookups = markFocus(in: filteredLookups, focusKeys: focusKeys)
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)

        return VocabularySyncResult(
            lookups: markedLookups,
            cacheURL: localURL,
            sourceModifiedAt: attributes?[.modificationDate] as? Date,
            filteredChineseWordCount: uniqueWordKeys(sourceLookups).count - uniqueWordKeys(filteredLookups).count,
            filteredChineseLookupCount: sourceLookups.count - filteredLookups.count,
            focusCandidateCount: focusKeys.count,
            unmatchedFocusCandidateCount: focusKeys.subtracting(matchedFocusKeys(markedLookups, focusKeys: focusKeys)).count
        )
    }

    private func vocabularyCacheURL() throws -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = baseURL
            .appendingPathComponent("Kindle Pilot", isDirectory: true)
            .appendingPathComponent("Clippings", isDirectory: true)
            .appendingPathComponent("Vocabulary", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vocab.db")
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func readLookups(from url: URL) throws -> [VocabularyLookup] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            defer { sqlite3_close(database) }
            let message: String
            if let database, let rawMessage = sqlite3_errmsg(database) {
                message = String(cString: rawMessage)
            } else {
                message = L("无法打开 vocab.db")
            }
            throw SQLiteError(message: message)
        }
        defer { sqlite3_close(database) }

        let query = """
        select
            l.id as lookup_id,
            l.word_key,
            w.word,
            w.stem,
            w.lang as word_lang,
            l.book_key,
            b.title as book_title,
            b.authors as authors,
            b.lang as book_lang,
            l.pos,
            l.usage,
            l.timestamp
        from LOOKUPS l
        join WORDS w on l.word_key = w.id
        join BOOK_INFO b on l.book_key = b.id
        order by lower(w.word), l.timestamp, l.pos
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var lookups: [VocabularyLookup] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = columnInt64(statement, 11)
            lookups.append(
                VocabularyLookup(
                    id: columnText(statement, 0),
                    wordKey: columnText(statement, 1),
                    word: columnText(statement, 2),
                    stem: columnText(statement, 3),
                    wordLanguage: columnText(statement, 4),
                    bookKey: columnText(statement, 5),
                    bookTitle: columnText(statement, 6).nilIfEmpty ?? "Untitled",
                    authors: columnText(statement, 7),
                    bookLanguage: columnText(statement, 8),
                    position: columnText(statement, 9).nilIfEmpty,
                    usage: normalizeUsage(columnText(statement, 10)),
                    timestamp: timestamp,
                    lookedUpAt: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                    isFocus: false
                )
            )
        }

        return lookups
    }

    private func makePlainText(
        _ lookups: [VocabularyLookup],
        options: VocabularyExportOptions
    ) -> String {
        var output: [String] = [L("Kindle 生词本"), ""]
        let sortedGroups = sortedWordGroups(lookups)

        guard options.includeDetails else {
            output.append(
                contentsOf: sortedGroups.enumerated().compactMap { index, group in
                    guard let first = group.first else {
                        return nil
                    }
                    return "\(index + 1). \(first.wordDisplayTitle)"
                }
            )
            return output.joined(separator: "\n")
        }

        for group in sortedGroups {
            guard let first = group.first else {
                continue
            }

            let title = first.isFocus ? "\(first.wordDisplayTitle) ★" : first.wordDisplayTitle
            output.append(title)
            output.append(String(repeating: "=", count: title.count))

            for lookup in group.sorted(by: lookupSort) {
                output.append("")
                output.append(lookup.bookDisplayTitle)

                let details = [
                    lookup.position.map { LF("位置 %@", $0) },
                    lookup.lookedUpAt.map { exportDateFormatter.string(from: $0) }
                ].compactMap { $0 }

                if !details.isEmpty {
                    output.append(details.joined(separator: " · "))
                }

                if !lookup.usage.isEmpty {
                    output.append(lookup.usage)
                }
            }

            output.append("")
        }

        return output.joined(separator: "\n")
    }

    private func sortedWordGroups(_ lookups: [VocabularyLookup]) -> [[VocabularyLookup]] {
        let grouped = Dictionary(grouping: lookups, by: \.wordKey)
        return grouped.values.sorted { lhs, rhs in
            let left = lhs.first
            let right = rhs.first

            if (left?.isFocus ?? false) != (right?.isFocus ?? false) {
                return left?.isFocus == true
            }

            return (left?.wordDisplayTitle ?? "")
                .localizedStandardCompare(right?.wordDisplayTitle ?? "") == .orderedAscending
        }
    }

    private func lookupSort(_ lhs: VocabularyLookup, _ rhs: VocabularyLookup) -> Bool {
        let leftTime = lhs.timestamp ?? 0
        let rightTime = rhs.timestamp ?? 0
        if leftTime != rightTime {
            return leftTime < rightTime
        }
        return (lhs.position ?? "") < (rhs.position ?? "")
    }

    private func markFocus(in lookups: [VocabularyLookup], focusKeys: Set<String>) -> [VocabularyLookup] {
        lookups.map { lookup in
            var copy = lookup
            copy.isFocus = !lookupFocusKeys(lookup).isDisjoint(with: focusKeys)
            return copy
        }
    }

    private func matchedFocusKeys(_ lookups: [VocabularyLookup], focusKeys: Set<String>) -> Set<String> {
        var matched = Set<String>()
        for lookup in lookups {
            matched.formUnion(lookupFocusKeys(lookup).intersection(focusKeys))
        }
        return matched
    }

    private func lookupFocusKeys(_ lookup: VocabularyLookup) -> Set<String> {
        Set([lookup.word, lookup.stem].compactMap(VocabularyNormalizer.normalizedSingleWord))
    }

    private func isChineseLookup(_ lookup: VocabularyLookup) -> Bool {
        lookup.wordLanguage.lowercased().hasPrefix("zh")
            || VocabularyNormalizer.containsCJK(lookup.word)
            || VocabularyNormalizer.containsCJK(lookup.stem)
    }

    private func uniqueWordKeys(_ lookups: [VocabularyLookup]) -> Set<String> {
        Set(lookups.map(\.wordKey))
    }

    private func normalizeUsage(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func columnInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    private var exportDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private struct SQLiteError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        LF("读取 vocab.db 失败: %@", message)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
