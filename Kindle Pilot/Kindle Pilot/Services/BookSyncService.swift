import Foundation

struct KindleRemoteBook: Hashable {
    let remotePath: String

    var fileName: String {
        URL(fileURLWithPath: remotePath).lastPathComponent
    }

    var title: String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}

struct KindleBookDuplicateMatch: Identifiable {
    let id = UUID()
    let localURL: URL
    let localTitle: String
    let existingBooks: [KindleRemoteBook]
}

final class BookSyncService {
    static let supportedExtensions: Set<String> = ["azw3", "mobi", "epub", "pdf"]

    private let connectionService: ConnectionService

    init(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    static func isSupportedBookURL(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func bookTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func normalizedBookTitle(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func duplicateBooks(
        settings: ConnectionSettings,
        localURLs: [URL],
        remoteDirectory: String = "/mnt/us/documents"
    ) async throws -> [KindleBookDuplicateMatch] {
        let existingBooks = try await listRemoteBooks(
            settings: settings,
            remoteDirectory: remoteDirectory
        )
        let existingBooksByTitle = Dictionary(
            grouping: existingBooks,
            by: { Self.normalizedBookTitle($0.title) }
        )

        return localURLs.compactMap { localURL in
            let localTitle = Self.bookTitle(for: localURL)
            let normalizedTitle = Self.normalizedBookTitle(localTitle)
            guard !normalizedTitle.isEmpty,
                  let matches = existingBooksByTitle[normalizedTitle],
                  !matches.isEmpty else {
                return nil
            }

            return KindleBookDuplicateMatch(
                localURL: localURL,
                localTitle: localTitle,
                existingBooks: matches.sorted {
                    $0.remotePath.localizedStandardCompare($1.remotePath) == .orderedAscending
                }
            )
        }
    }

    func uploadBook(
        settings: ConnectionSettings,
        localURL: URL,
        remoteDirectory: String = "/mnt/us/documents",
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> String {
        let client = connectionService.makeClient(settings: settings)
        let remotePath = "\(remoteDirectory)/\(localURL.lastPathComponent)"
        _ = try await client.exec(command: "mkdir -p \(shellQuote(remoteDirectory))")
        _ = try await client.upload(localURL: localURL, to: remotePath, progress: progress)
        return remotePath
    }

    private func listRemoteBooks(
        settings: ConnectionSettings,
        remoteDirectory: String
    ) async throws -> [KindleRemoteBook] {
        let client = connectionService.makeClient(settings: settings)
        let quotedDirectory = shellQuote(remoteDirectory)
        let extensionPredicates = Self.supportedExtensions
            .sorted()
            .map { "-iname \(shellQuote("*.\($0)"))" }
            .joined(separator: " -o ")
        let command = "if [ -d \(quotedDirectory) ]; then find \(quotedDirectory) -type f \\( \(extensionPredicates) \\) -print; fi"
        let result = try await client.exec(command: command)

        return result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { KindleRemoteBook(remotePath: $0) }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
