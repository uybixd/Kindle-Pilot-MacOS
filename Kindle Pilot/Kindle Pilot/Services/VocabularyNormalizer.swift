import Foundation

enum VocabularyNormalizer {
    nonisolated static func normalizedSingleWord(_ content: String) -> String? {
        let text = content
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }

        let parts = text
            .split(separator: " ")
            .map { stripEdgePunctuation(String($0)) }
            .filter { !$0.isEmpty }

        guard parts.count == 1 else { return nil }
        let word = parts[0]
        guard !containsCJK(word) else { return nil }
        guard word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }
        guard word.unicodeScalars.allSatisfy(isWordScalar) else {
            return nil
        }
        return word.lowercased()
    }

    nonisolated static func isSingleSelection(_ content: String) -> Bool {
        if normalizedSingleWord(content) != nil {
            return true
        }

        let text = stripEdgePunctuation(
            content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard text.count == 1 else {
            return false
        }
        return containsCJK(text)
    }

    nonisolated static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: isCJK)
    }

    nonisolated private static func stripEdgePunctuation(_ value: String) -> String {
        var scalars = Array(value.unicodeScalars)

        while let first = scalars.first, isEdgePunctuation(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, isEdgePunctuation(last) {
            scalars.removeLast()
        }

        return String(String.UnicodeScalarView(scalars))
    }

    nonisolated private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || scalar == "'"
            || scalar == "’"
            || scalar == "-"
            || scalar == "‐"
            || scalar == "‑"
            || scalar == "–"
    }

    nonisolated private static func isEdgePunctuation(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
    }

    nonisolated private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
            || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value)
            || (0x2B820...0x2CEAF).contains(value)
            || (0x2CEB0...0x2EBEF).contains(value)
            || (0x30000...0x3134F).contains(value)
    }
}
