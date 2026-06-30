import CryptoKit
import Foundation

enum ClippingKind: String, CaseIterable, Codable {
    case highlight
    case note
    case bookmark
    case unknown

    var title: String {
        switch self {
        case .highlight:
            return L("标注")
        case .note:
            return L("笔记")
        case .bookmark:
            return L("书签")
        case .unknown:
            return L("未知")
        }
    }
}

struct Clipping: Identifiable, Hashable, Codable {
    let id: String
    let bookID: String
    let bookTitle: String
    let author: String?
    let kind: ClippingKind
    let location: String?
    let locationStart: Int?
    let locationEnd: Int?
    let page: String?
    let addedAt: Date?
    let metadata: String
    let text: String
    let raw: String
    let kindleNotes: [KindleNote]

    var bookDisplayTitle: String {
        if let author, !author.isEmpty {
            return "\(bookTitle) (\(author))"
        }
        return bookTitle
    }

    var referenceText: String {
        let parts = [
            page.map { LF("页 %@", $0) },
            location.map { LF("位置 %@", $0) }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    static func stableID(
        bookTitle: String,
        author: String?,
        metadata: String,
        text: String
    ) -> String {
        hash([bookTitle, author ?? "", metadata, text].joined(separator: "\u{1F}"))
    }

    static func stableBookID(bookTitle: String, author: String?) -> String {
        hash([bookTitle, author ?? ""].joined(separator: "\u{1F}"))
    }

    func attaching(_ notes: [KindleNote]) -> Clipping {
        Clipping(
            id: id,
            bookID: bookID,
            bookTitle: bookTitle,
            author: author,
            kind: kind,
            location: location,
            locationStart: locationStart,
            locationEnd: locationEnd,
            page: page,
            addedAt: addedAt,
            metadata: metadata,
            text: text,
            raw: raw,
            kindleNotes: notes
        )
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct KindleNote: Identifiable, Hashable, Codable {
    let id: String
    let location: String?
    let locationStart: Int?
    let locationEnd: Int?
    let page: String?
    let addedAt: Date?
    let metadata: String
    let text: String
    let raw: String

    var referenceText: String {
        let parts = [
            page.map { LF("页 %@", $0) },
            location.map { LF("位置 %@", $0) }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }
}

struct ClippingsParseResult {
    let clippings: [Clipping]
    let vocabularyFocusCandidates: Set<String>
    let filteredSingleSelectionCount: Int
    let filteredDuplicateCount: Int
}

struct ClippingBookSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String?
    let count: Int

    var displayTitle: String {
        if let author, !author.isEmpty {
            return "\(title) (\(author))"
        }
        return title
    }
}

enum ClippingsExportFormat {
    case markdown
    case csv
    case plainText

    var title: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .csv:
            return "CSV"
        case .plainText:
            return "TXT"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .csv:
            return "csv"
        case .plainText:
            return "txt"
        }
    }

    var defaultFileName: String {
        switch self {
        case .markdown:
            return "Kindle_Clippings.md"
        case .csv:
            return "Kindle_Clippings.csv"
        case .plainText:
            return "Kindle_Clippings.txt"
        }
    }
}

struct ClippingsExportOptions {
    var includeDetails = true
}

enum ClippingsSortOrder: String, CaseIterable, Identifiable {
    case addedAt
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addedAt:
            return L("按添加时间")
        case .location:
            return L("按位置")
        }
    }
}

struct ClippingsSyncResult {
    let clippings: [Clipping]
    let cacheURL: URL
    let sourceModifiedAt: Date?
    let vocabularyFocusCandidates: Set<String>
    let filteredSingleSelectionCount: Int
    let filteredDuplicateCount: Int
}
