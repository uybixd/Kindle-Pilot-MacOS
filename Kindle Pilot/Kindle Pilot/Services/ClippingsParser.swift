import Foundation

final class ClippingsParser {
    func parse(_ text: String) -> [Clipping] {
        parseDetailed(text).clippings
    }

    func parseDetailed(_ text: String) -> ClippingsParseResult {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))

        let records = normalized
            .components(separatedBy: "\n==========")
            .compactMap(parseBlock)

        let focusCandidates = Set(records.compactMap { record in
            VocabularyNormalizer.normalizedSingleWord(record.text)
        })
        let displayRecords = records.filter { !isSingleSelectionRecord($0) }
        let deduplicationResult = deduplicateContainedClippings(displayRecords)

        return ClippingsParseResult(
            clippings: mergeKindleNotes(deduplicationResult.records),
            vocabularyFocusCandidates: focusCandidates,
            filteredSingleSelectionCount: records.count - displayRecords.count,
            filteredDuplicateCount: deduplicationResult.filteredCount
        )
    }

    private func parseBlock(_ block: String) -> Clipping? {
        let raw = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let lines = raw.components(separatedBy: "\n")
        guard let titleIndex = lines.firstIndex(where: { !$0.trimmed.isEmpty }) else {
            return nil
        }

        guard let metadataIndex = lines[(titleIndex + 1)...].firstIndex(where: { !$0.trimmed.isEmpty }) else {
            return nil
        }

        let titleLine = lines[titleIndex].trimmed
        let metadata = lines[metadataIndex].trimmed
        let titleParts = parseTitle(titleLine)

        var contentStart = metadataIndex + 1
        while contentStart < lines.count, lines[contentStart].trimmed.isEmpty {
            contentStart += 1
        }

        let text: String
        if contentStart < lines.count {
            text = lines[contentStart...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = ""
        }

        let locationRange = parseLocationRange(metadata)
        let id = Clipping.stableID(
            bookTitle: titleParts.title,
            author: titleParts.author,
            metadata: metadata,
            text: text
        )
        let bookID = Clipping.stableBookID(bookTitle: titleParts.title, author: titleParts.author)

        return Clipping(
            id: id,
            bookID: bookID,
            bookTitle: titleParts.title,
            author: titleParts.author,
            kind: parseKind(metadata),
            location: locationRange?.display,
            locationStart: locationRange?.start,
            locationEnd: locationRange?.end,
            page: firstMatch(
                patterns: [
                    "(?i)page\\s*[:：]?\\s*([0-9][0-9,\\-–—]*)",
                    "第\\s*([0-9][0-9,\\-–—]*)\\s*页",
                    "页码\\s*[:：]?\\s*([0-9][0-9,\\-–—]*)"
                ],
                in: metadata
            ),
            addedAt: parseAddedAt(metadata),
            metadata: metadata,
            text: text,
            raw: raw,
            kindleNotes: []
        )
    }

    private func mergeKindleNotes(_ records: [Clipping]) -> [Clipping] {
        let notes = records.filter { $0.kind == .note }
        let targets = records.filter { $0.kind == .highlight }
        var notesByTargetID: [Clipping.ID: [KindleNote]] = [:]
        var matchedNoteIDs = Set<Clipping.ID>()

        for note in notes {
            guard let target = bestKindleNoteTarget(for: note, candidates: targets) else {
                continue
            }

            notesByTargetID[target.id, default: []].append(kindleNote(from: note))
            matchedNoteIDs.insert(note.id)
        }

        return records.compactMap { record in
            if record.kind == .note, matchedNoteIDs.contains(record.id) {
                return nil
            }

            let attachedNotes = (notesByTargetID[record.id] ?? []).sorted { lhs, rhs in
                if let left = lhs.locationStart, let right = rhs.locationStart, left != right {
                    return left < right
                }
                if let left = lhs.addedAt, let right = rhs.addedAt {
                    return left < right
                }
                return lhs.id < rhs.id
            }

            return record.attaching(attachedNotes)
        }
    }

    private func isSingleSelectionRecord(_ record: Clipping) -> Bool {
        guard record.kind == .highlight || record.kind == .note else {
            return false
        }
        return VocabularyNormalizer.isSingleSelection(record.text)
    }

    private func deduplicateContainedClippings(_ records: [Clipping]) -> (records: [Clipping], filteredCount: Int) {
        let candidates = records.enumerated().compactMap { index, record in
            deduplicationCandidate(for: record, at: index)
        }
        let candidatesByKey = Dictionary(grouping: candidates, by: \.key)
        var removedIndexes = Set<Int>()

        for candidate in candidates {
            guard !removedIndexes.contains(candidate.index),
                  let peerCandidates = candidatesByKey[candidate.key] else {
                continue
            }

            for peer in peerCandidates where peer.index != candidate.index {
                guard areCompatibleDuplicateRanges(candidate.record, peer.record),
                      shouldRemove(candidate, becauseOf: peer) else {
                    continue
                }

                removedIndexes.insert(candidate.index)
                break
            }
        }

        return (
            records: records.enumerated().compactMap { index, record in
                removedIndexes.contains(index) ? nil : record
            },
            filteredCount: removedIndexes.count
        )
    }

    private func deduplicationCandidate(
        for record: Clipping,
        at index: Int
    ) -> ClippingDeduplicationCandidate? {
        guard record.kind == .highlight || record.kind == .note else {
            return nil
        }

        let comparableText = normalizedComparableText(record.text)
        guard !comparableText.isEmpty else {
            return nil
        }

        return ClippingDeduplicationCandidate(
            index: index,
            key: ClippingDeduplicationKey(bookID: record.bookID, kind: record.kind),
            record: record,
            comparableText: comparableText,
            compactedText: compactedComparableText(comparableText)
        )
    }

    private func shouldRemove(
        _ candidate: ClippingDeduplicationCandidate,
        becauseOf peer: ClippingDeduplicationCandidate
    ) -> Bool {
        if candidate.comparableText == peer.comparableText {
            return peer.index < candidate.index
        }

        guard peer.comparableText.count > candidate.comparableText.count else {
            return false
        }

        return peer.comparableText.contains(candidate.comparableText)
            || peer.compactedText.contains(candidate.compactedText)
    }

    private func areCompatibleDuplicateRanges(_ lhs: Clipping, _ rhs: Clipping) -> Bool {
        guard let leftStart = lhs.locationStart ?? lhs.locationEnd,
              let rightStart = rhs.locationStart ?? rhs.locationEnd else {
            return false
        }

        let leftEnd = lhs.locationEnd ?? leftStart
        let rightEnd = rhs.locationEnd ?? rightStart
        return rangeDistance(startA: leftStart, endA: leftEnd, startB: rightStart, endB: rightEnd) <= 1
    }

    private func normalizedComparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactedComparableText(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private func bestKindleNoteTarget(for note: Clipping, candidates: [Clipping]) -> Clipping? {
        var best: (score: KindleNoteMatchScore, clipping: Clipping)?

        for candidate in candidates where candidate.bookID == note.bookID {
            guard let score = kindleNoteMatchScore(note: note, candidate: candidate) else {
                continue
            }

            if let currentBest = best {
                if score < currentBest.score {
                    best = (score, candidate)
                }
            } else {
                best = (score, candidate)
            }
        }

        return best?.clipping
    }

    private func kindleNoteMatchScore(note: Clipping, candidate: Clipping) -> KindleNoteMatchScore? {
        guard let noteStart = note.locationStart,
              let candidateStart = candidate.locationStart else {
            return nil
        }

        let noteEnd = note.locationEnd ?? noteStart
        let candidateEnd = candidate.locationEnd ?? candidateStart
        let contains = candidateStart <= noteStart && noteStart <= candidateEnd
        let overlaps = noteStart <= candidateEnd && noteEnd >= candidateStart
        guard contains || overlaps else {
            return nil
        }

        return KindleNoteMatchScore(
            containmentScore: contains ? 0 : 1,
            distance: rangeDistance(
                startA: noteStart,
                endA: noteEnd,
                startB: candidateStart,
                endB: candidateEnd
            ),
            span: candidateEnd - candidateStart
        )
    }

    private func rangeDistance(startA: Int, endA: Int, startB: Int, endB: Int) -> Int {
        if startA <= endB && endA >= startB {
            return 0
        }
        if endA < startB {
            return startB - endA
        }
        return startA - endB
    }

    private func kindleNote(from clipping: Clipping) -> KindleNote {
        KindleNote(
            id: clipping.id,
            location: clipping.location,
            locationStart: clipping.locationStart,
            locationEnd: clipping.locationEnd,
            page: clipping.page,
            addedAt: clipping.addedAt,
            metadata: clipping.metadata,
            text: clipping.text,
            raw: clipping.raw
        )
    }

    private func parseTitle(_ line: String) -> (title: String, author: String?) {
        guard line.hasSuffix(")"), let openIndex = line.lastIndex(of: "(") else {
            return (line, nil)
        }

        let title = String(line[..<openIndex]).trimmed
        let authorStart = line.index(after: openIndex)
        let authorEnd = line.index(before: line.endIndex)
        let author = String(line[authorStart..<authorEnd]).trimmed

        return (title.isEmpty ? line : title, author.isEmpty ? nil : author)
    }

    private func parseKind(_ metadata: String) -> ClippingKind {
        let lowercased = metadata.lowercased()
        if lowercased.contains("highlight") || metadata.contains("标注") || metadata.contains("高亮") {
            return .highlight
        }
        if lowercased.contains("note") || metadata.contains("笔记") {
            return .note
        }
        if lowercased.contains("bookmark") || metadata.contains("书签") {
            return .bookmark
        }
        return .unknown
    }

    private func parseAddedAt(_ metadata: String) -> Date? {
        let markers = ["Added on", "添加于"]
        let candidatesFromMarkers = markers.compactMap { marker -> String? in
            guard let range = metadata.range(of: marker, options: [.caseInsensitive]) else {
                return nil
            }
            return String(metadata[range.upperBound...]).trimmed
        }

        let pipeCandidate = metadata
            .components(separatedBy: "|")
            .last?
            .replacingOccurrences(of: "Added on", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "添加于", with: "")
            .trimmed

        let candidates = candidatesFromMarkers + [pipeCandidate].compactMap { $0 }

        for candidate in candidates where !candidate.isEmpty {
            if let date = parseDate(candidate) {
                return date
            }
        }

        return nil
    }

    private func parseLocationRange(_ metadata: String) -> (start: Int, end: Int, display: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)(?:位置|location|loc\\.)\\s*#?\\s*([0-9]+)(?:\\s*[-–—]\\s*#?\\s*([0-9]+))?"
        ) else {
            return nil
        }

        let range = NSRange(metadata.startIndex..<metadata.endIndex, in: metadata)
        guard let match = regex.firstMatch(in: metadata, range: range),
              match.numberOfRanges > 1,
              let startRange = Range(match.range(at: 1), in: metadata),
              let start = Int(metadata[startRange]) else {
            return nil
        }

        let end: Int
        if match.numberOfRanges > 2,
           let endRange = Range(match.range(at: 2), in: metadata),
           let parsedEnd = Int(metadata[endRange]) {
            end = parsedEnd
        } else {
            end = start
        }

        let display = end == start ? "\(start)" : "\(start)-\(end)"
        return (start, end, display)
    }

    private func parseDate(_ value: String) -> Date? {
        let formats: [(String, Locale)] = [
            ("EEEE, MMMM d, yyyy h:mm:ss a", Locale(identifier: "en_US_POSIX")),
            ("EEEE, MMMM d, yyyy h:mm a", Locale(identifier: "en_US_POSIX")),
            ("MMMM d, yyyy h:mm:ss a", Locale(identifier: "en_US_POSIX")),
            ("MMMM d, yyyy h:mm a", Locale(identifier: "en_US_POSIX")),
            ("yyyy年M月d日 EEEE ah:mm:ss", Locale(identifier: "zh_CN")),
            ("yyyy年M月d日 EEEE ah:mm", Locale(identifier: "zh_CN")),
            ("yyyy年M月d日 ah:mm:ss", Locale(identifier: "zh_CN")),
            ("yyyy年M月d日 ah:mm", Locale(identifier: "zh_CN"))
        ]

        for (format, locale) in formats {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = format
            formatter.isLenient = true
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func firstMatch(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let value = String(text[valueRange]).trimmed
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }
}

private struct KindleNoteMatchScore: Comparable {
    let containmentScore: Int
    let distance: Int
    let span: Int

    static func < (lhs: KindleNoteMatchScore, rhs: KindleNoteMatchScore) -> Bool {
        if lhs.containmentScore != rhs.containmentScore {
            return lhs.containmentScore < rhs.containmentScore
        }
        if lhs.distance != rhs.distance {
            return lhs.distance < rhs.distance
        }
        return lhs.span < rhs.span
    }
}

private struct ClippingDeduplicationKey: Hashable {
    let bookID: String
    let kind: ClippingKind
}

private struct ClippingDeduplicationCandidate {
    let index: Int
    let key: ClippingDeduplicationKey
    let record: Clipping
    let comparableText: String
    let compactedText: String
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .kindleClippingBoundaryCharacters)
    }
}

private extension CharacterSet {
    static let kindleClippingBoundaryCharacters: CharacterSet = {
        var characters = CharacterSet.whitespacesAndNewlines
        characters.insert(charactersIn: "\u{feff}")
        return characters
    }()
}
