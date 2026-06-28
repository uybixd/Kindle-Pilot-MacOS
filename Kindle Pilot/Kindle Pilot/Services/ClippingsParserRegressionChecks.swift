#if DEBUG
import Foundation

enum ClippingsParserRegressionChecks {
    static func runAll() throws {
        try testEmbeddedBOMTitleDoesNotSplitBook()
        try testContainedDuplicateHighlightsKeepLongerText()
        try testContainedDuplicateNotesKeepLongerText()
    }

    static func assertAll() {
        do {
            try runAll()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    private static func testEmbeddedBOMTitleDoesNotSplitBook() throws {
        let expectedTitle = "Just for Fun : The Story of an Accidental Revolutionary"
        let text = """
        \(expectedTitle) (Linus Benedict Torvalds)
        - Your Highlight on Location 10-11 | Added on Thursday, June 11, 2026 10:00:00 PM

        First highlight
        ==========
        \u{feff}\(expectedTitle) (Linus Benedict Torvalds)
        - Your Highlight on Location 12-13 | Added on Thursday, June 11, 2026 10:01:00 PM

        Second highlight
        ==========
        """

        let clippings = ClippingsParser().parse(text)
        let bookIDs = Set(clippings.map(\.bookID))
        let titles = Set(clippings.map(\.bookTitle))

        guard clippings.count == 2 else {
            throw failure("expected 2 parsed clippings, got \(clippings.count)")
        }
        guard bookIDs.count == 1 else {
            throw failure("expected embedded BOM titles to share one bookID, got \(bookIDs.count)")
        }
        guard titles == [expectedTitle] else {
            throw failure("expected normalized title without embedded BOM")
        }
    }

    private static func testContainedDuplicateHighlightsKeepLongerText() throws {
        let text = """
        Book (Author)
        - Your Highlight on Location 1517 | Added on Thursday, June 11, 2026 10:00:00 PM

        我们追悼了过去的人，还要发愿：要自己和别
        ==========
        Book (Author)
        - Your Highlight on Location 1517-1518 | Added on Thursday, June 11, 2026 10:01:00 PM

        我们追悼了过去的人，还要发愿：要自己和别人，都纯洁聪明勇猛向上。要除去虚伪的脸谱。
        ==========
        Book (Author)
        - Your Highlight on Location 1517-1518 | Added on Thursday, June 11, 2026 10:01:00 PM

        我们追悼了过去的人，还要发愿：要自己和别人，都纯洁聪明勇猛向上。要除去虚伪的脸谱。
        ==========
        Book (Author)
        - Your Highlight on Location 1519 | Added on Thursday, June 11, 2026 10:02:00 PM

        另一条独立摘抄
        ==========
        """

        let result = ClippingsParser().parseDetailed(text)

        guard result.clippings.count == 2 else {
            throw failure("expected 2 clippings after duplicate highlight filtering, got \(result.clippings.count)")
        }
        guard result.filteredDuplicateCount == 2 else {
            throw failure("expected 2 filtered duplicate highlights, got \(result.filteredDuplicateCount)")
        }
        guard result.clippings.contains(where: { $0.text.contains("要除去虚伪的脸谱") }) else {
            throw failure("expected longer duplicate highlight to be retained")
        }
        guard !result.clippings.contains(where: { $0.text == "我们追悼了过去的人，还要发愿：要自己和别" }) else {
            throw failure("expected shorter duplicate highlight to be removed")
        }
    }

    private static func testContainedDuplicateNotesKeepLongerText() throws {
        let text = """
        Book (Author)
        - Your Note on Location 200 | Added on Thursday, June 11, 2026 10:00:00 PM

        shorter note
        ==========
        Book (Author)
        - Your Note on Location 200-201 | Added on Thursday, June 11, 2026 10:01:00 PM

        shorter note with extra detail
        ==========
        """

        let result = ClippingsParser().parseDetailed(text)

        guard result.clippings.count == 1 else {
            throw failure("expected 1 note after duplicate note filtering, got \(result.clippings.count)")
        }
        guard result.filteredDuplicateCount == 1 else {
            throw failure("expected 1 filtered duplicate note, got \(result.filteredDuplicateCount)")
        }
        guard result.clippings.first?.text == "shorter note with extra detail" else {
            throw failure("expected longer duplicate note to be retained")
        }
    }

    private static func failure(_ message: String) -> ClippingsParserRegressionFailure {
        ClippingsParserRegressionFailure(message: message)
    }
}

private struct ClippingsParserRegressionFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        "Clippings parser regression failed: \(message)"
    }
}
#endif
