import Foundation

final class ClippingsService {
    private let connectionService: ConnectionService
    private let parser: ClippingsParser

    init(connectionService: ConnectionService, parser: ClippingsParser = ClippingsParser()) {
        self.connectionService = connectionService
        self.parser = parser
    }

    func downloadClippings(settings: ConnectionSettings, to localURL: URL) async throws {
        let client = connectionService.makeClient(settings: settings)
        _ = try await client.download(remotePath: "/mnt/us/documents/My Clippings.txt", to: localURL)
    }

    func downloadVocabulary(settings: ConnectionSettings, to localURL: URL) async throws {
        let client = connectionService.makeClient(settings: settings)
        _ = try await client.download(remotePath: "/mnt/us/system/vocabulary/vocab.db", to: localURL)
    }

    func syncClippings(settings: ConnectionSettings) async throws -> ClippingsSyncResult {
        let localURL = try clippingsCacheURL()
        try await downloadClippings(settings: settings, to: localURL)
        return try loadClippings(from: localURL)
    }

    func importClippings(from sourceURL: URL) throws -> ClippingsSyncResult {
        let localURL = try clippingsCacheURL()
        try copyReplacingItem(from: sourceURL, to: localURL)
        return try loadClippings(from: localURL)
    }

    func loadCachedClippings() throws -> ClippingsSyncResult? {
        let localURL = try clippingsCacheURL()
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        return try loadClippings(from: localURL)
    }

    func cachedClippingsURL() throws -> URL {
        try clippingsCacheURL()
    }

    func export(
        _ clippings: [Clipping],
        format: ClippingsExportFormat,
        options: ClippingsExportOptions,
        to url: URL
    ) throws {
        let output: String
        switch format {
        case .markdown:
            output = makeMarkdown(clippings, options: options)
        case .csv:
            output = makeCSV(clippings, options: options)
        case .plainText:
            output = makePlainText(clippings, options: options)
        }

        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadClippings(from url: URL) throws -> ClippingsSyncResult {
        let text = try readText(from: url)
        let parsed = parser.parseDetailed(text)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return ClippingsSyncResult(
            clippings: parsed.clippings,
            cacheURL: url,
            sourceModifiedAt: attributes?[.modificationDate] as? Date,
            vocabularyFocusCandidates: parsed.vocabularyFocusCandidates,
            filteredSingleSelectionCount: parsed.filteredSingleSelectionCount,
            filteredDuplicateCount: parsed.filteredDuplicateCount
        )
    }

    private func clippingsCacheURL() throws -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = baseURL
            .appendingPathComponent("Kindle Pilot", isDirectory: true)
            .appendingPathComponent("Clippings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("My Clippings.txt")
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func makeMarkdown(_ clippings: [Clipping], options: ClippingsExportOptions) -> String {
        var output: [String] = []
        let grouped = Dictionary(grouping: clippings, by: \.bookID)

        for bookID in grouped.keys.sorted(by: { lhs, rhs in
            let left = grouped[lhs]?.first?.bookDisplayTitle ?? ""
            let right = grouped[rhs]?.first?.bookDisplayTitle ?? ""
            return left.localizedStandardCompare(right) == .orderedAscending
        }) {
            guard let bookClippings = grouped[bookID], let first = bookClippings.first else {
                continue
            }

            if !output.isEmpty {
                output.append("")
                output.append("")
            }

            output.append(contentsOf: markdownBookHeader(for: first))

            var isFirstClipping = true
            for clipping in bookClippings {
                if isFirstClipping {
                    isFirstClipping = false
                } else {
                    output.append(contentsOf: markdownBlockSpacer())
                }

                if clipping.kind == .note {
                    output.append(L("Kindle 批注:"))
                    output.append("")
                    output.append(contentsOf: markdownTextLines(clipping.text))
                } else {
                    output.append(contentsOf: markdownTextLines(clipping.text))

                    for note in clipping.kindleNotes {
                        output.append("")
                        output.append(contentsOf: markdownNestedKindleNoteBlock(note))
                    }
                }

                if let detail = markdownDetailLine(for: clipping, includeDetails: options.includeDetails) {
                    output.append("")
                    output.append(detail)
                }
            }
        }

        return output.joined(separator: "\n")
    }

    private func makeCSV(_ clippings: [Clipping], options: ClippingsExportOptions) -> String {
        let rows = clippings.enumerated().map { index, clipping in
            let basicValues = [
                clipping.bookTitle,
                clipping.author ?? "",
                "\(index + 1)",
                clipping.text,
                clipping.kindleNotes.map(\.text).joined(separator: "\n\n")
            ]

            guard options.includeDetails else {
                return basicValues.map(csvEscape).joined(separator: ",")
            }

            return ([
                clipping.bookTitle,
                clipping.author ?? "",
                "\(index + 1)",
                clipping.page ?? "",
                clipping.location ?? "",
                clipping.addedAt.map { exportDateFormatter.string(from: $0) } ?? "",
                clipping.text,
                clipping.kindleNotes.map(\.text).joined(separator: "\n\n"),
                clipping.metadata
            ]).map(csvEscape).joined(separator: ",")
        }

        let header = options.includeDetails
            ? "book_title,author,index,page,location,added_at,text,kindle_notes,metadata"
            : "book_title,author,index,text,kindle_notes"

        return ([header] + rows).joined(separator: "\n")
    }

    private func makePlainText(_ clippings: [Clipping], options: ClippingsExportOptions) -> String {
        var output: [String] = [L("Kindle 摘抄"), ""]
        let grouped = Dictionary(grouping: clippings, by: \.bookID)

        for bookID in grouped.keys.sorted(by: { lhs, rhs in
            let left = grouped[lhs]?.first?.bookDisplayTitle ?? ""
            let right = grouped[rhs]?.first?.bookDisplayTitle ?? ""
            return left.localizedStandardCompare(right) == .orderedAscending
        }) {
            guard let bookClippings = grouped[bookID], let first = bookClippings.first else {
                continue
            }

            output.append(first.bookDisplayTitle)
            output.append(String(repeating: "=", count: first.bookDisplayTitle.count))
            output.append("")

            for (index, clipping) in bookClippings.enumerated() {
                let details = clippingDetailText(
                    index: index + 1,
                    for: clipping,
                    includeDetails: options.includeDetails
                )
                if !details.isEmpty {
                    output.append(details)
                }

                if clipping.kind == .note {
                    output.append(L("Kindle 批注:"))
                }
                output.append(clipping.text.isEmpty ? L("_无内容_") : clipping.text)

                for note in clipping.kindleNotes {
                    output.append("")
                    output.append(L("Kindle 批注:"))
                    output.append(note.text.isEmpty ? L("_无内容_") : note.text)

                    if options.includeDetails, let addedAt = note.addedAt {
                        output.append(LF("批注于: %@", exportDateFormatter.string(from: addedAt)))
                    }
                }

                output.append("")
            }
        }

        return output.joined(separator: "\n")
    }

    private func clippingDetailText(
        index: Int,
        for clipping: Clipping,
        includeDetails: Bool
    ) -> String {
        var parts = ["\(index)."]
        guard includeDetails else {
            return parts.joined(separator: " · ")
        }

        if !clipping.referenceText.isEmpty {
            parts.append(clipping.referenceText)
        }
        if let addedAt = clipping.addedAt {
            parts.append(exportDateFormatter.string(from: addedAt))
        }
        return parts.joined(separator: " · ")
    }

    private func markdownBookHeader(for clipping: Clipping) -> [String] {
        var lines = [
            "<p align=\"center\">",
            "  <strong>\(htmlEscaped(clipping.bookTitle))</strong>"
        ]

        if let author = clipping.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            lines[1] += "<br>"
            lines.append("  <sub>\(htmlEscaped(author))</sub>")
        }

        lines.append("</p>")
        lines.append("")
        lines.append("")
        return lines
    }

    private func markdownTextLines(_ value: String) -> [String] {
        let text = value.isEmpty ? L("_无内容_") : value
        return text.components(separatedBy: .newlines)
    }

    private func markdownNestedKindleNoteBlock(_ note: KindleNote) -> [String] {
        var lines = [
            "> <sub>\(L("Kindle 批注:"))</sub>",
            ">"
        ]

        lines.append(
            contentsOf: markdownTextLines(note.text).map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
        )
        return lines
    }

    private func markdownBlockSpacer() -> [String] {
        ["", "<p>&nbsp;</p>", ""]
    }

    private func markdownDetailLine(
        for clipping: Clipping,
        includeDetails: Bool
    ) -> String? {
        guard includeDetails else {
            return nil
        }

        return markdownDetailLine(
            addedAt: clipping.addedAt,
            page: clipping.page,
            location: clipping.location,
            locationStart: clipping.locationStart,
            locationEnd: clipping.locationEnd
        )
    }

    private func markdownDetailLine(
        for note: KindleNote,
        includeDetails: Bool
    ) -> String? {
        guard includeDetails else {
            return nil
        }

        return markdownDetailLine(
            addedAt: note.addedAt,
            page: note.page,
            location: note.location,
            locationStart: note.locationStart,
            locationEnd: note.locationEnd
        )
    }

    private func markdownDetailLine(
        addedAt: Date?,
        page: String?,
        location: String?,
        locationStart: Int?,
        locationEnd: Int?
    ) -> String? {
        var parts: [String] = []

        if let addedAt {
            parts.append(markdownDateFormatter.string(from: addedAt))
        }

        if let locationText = markdownLocationText(
            location: location,
            locationStart: locationStart,
            locationEnd: locationEnd
        ) {
            parts.append(locationText)
        } else if let page = page?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty {
            parts.append("P\(page)")
        }

        guard !parts.isEmpty else {
            return nil
        }

        return "<p align=\"right\"><sub>\(htmlEscaped(parts.joined(separator: " · ")))</sub></p>"
    }

    private func markdownLocationText(
        location: String?,
        locationStart: Int?,
        locationEnd: Int?
    ) -> String? {
        if let locationStart {
            let end = locationEnd ?? locationStart
            if end == locationStart {
                return "L\(locationStart)"
            }
            return "L\(locationStart)–\(end)"
        }

        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else {
            return nil
        }

        return "L\(location.replacingOccurrences(of: "-", with: "–"))"
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private var markdownDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd · HH:mm"
        return formatter
    }

    private var exportDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
