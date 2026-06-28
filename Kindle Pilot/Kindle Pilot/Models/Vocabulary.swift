import Foundation

struct VocabularyLookup: Identifiable, Hashable, Codable {
    let id: String
    let wordKey: String
    let word: String
    let stem: String
    let wordLanguage: String
    let bookKey: String
    let bookTitle: String
    let authors: String
    let bookLanguage: String
    let position: String?
    let usage: String
    let timestamp: Int64?
    let lookedUpAt: Date?
    var isFocus: Bool

    var wordDisplayTitle: String {
        if !stem.isEmpty, stem.caseInsensitiveCompare(word) != .orderedSame {
            return "\(word) (\(stem))"
        }
        return word
    }

    var bookDisplayTitle: String {
        if !authors.isEmpty {
            return "\(bookTitle) - \(authors)"
        }
        return bookTitle
    }
}

struct VocabularyWordSummary: Identifiable, Hashable {
    let id: String
    let word: String
    let stem: String
    let lookupCount: Int
    let isFocus: Bool

    var displayTitle: String {
        if !stem.isEmpty, stem.caseInsensitiveCompare(word) != .orderedSame {
            return "\(word) (\(stem))"
        }
        return word
    }
}

struct VocabularySyncResult {
    let lookups: [VocabularyLookup]
    let cacheURL: URL
    let sourceModifiedAt: Date?
    let filteredChineseWordCount: Int
    let filteredChineseLookupCount: Int
    let focusCandidateCount: Int
    let unmatchedFocusCandidateCount: Int
}

struct VocabularyExportOptions {
    var includeDetails = true
}
