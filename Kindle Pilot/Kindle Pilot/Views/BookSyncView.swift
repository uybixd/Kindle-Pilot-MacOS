import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct BookSyncView: View {
    @ObservedObject var model: KindlePilotViewModel
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = languageStore.preference

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("传书"), systemImage: "books.vertical")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    chooseBooks()
                } label: {
                    Label(L("选择书籍"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)

                Button {
                    dismiss()
                } label: {
                    Label(L("退出"), systemImage: "xmark.circle")
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isWorking)
            }

            Text(L("支持 azw3、mobi、epub、pdf，上传到 Kindle 的 /mnt/us/documents/。"))
                .foregroundStyle(.secondary)

            if !model.uploadItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.uploadProgressFraction)
                    Text(model.uploadProgressSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.uploadItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text(L("还没有选择书籍"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.uploadItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.status.systemImage)
                            .foregroundStyle(color(for: item.status))
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.fileName)
                                .lineLimit(1)
                            Text(detailText(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.status.title)
                                .foregroundStyle(color(for: item.status))

                            if shouldShowProgress(for: item) {
                                ProgressView(value: item.progressFraction)
                                    .frame(width: 130)
                                Text(progressText(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func detailText(for item: BookUploadItem) -> String {
        if item.status == .checking {
            return L("正在检查 Kindle 中是否已有同名书籍")
        }
        if let remotePath = item.remotePath {
            return remotePath
        }
        if let errorMessage = item.errorMessage {
            return errorMessage
        }
        return item.url.path
    }

    private func color(for status: BookUploadStatus) -> Color {
        switch status {
        case .checking:
            return .blue
        case .pending:
            return .secondary
        case .uploading:
            return .blue
        case .uploaded:
            return .green
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }

    private func shouldShowProgress(for item: BookUploadItem) -> Bool {
        switch item.status {
        case .uploading, .uploaded:
            return item.totalBytes > 0
        case .failed:
            return item.totalBytes > 0 && item.bytesSent > 0
        case .checking, .pending, .skipped:
            return false
        }
    }

    private func progressText(for item: BookUploadItem) -> String {
        let sentBytes = min(max(item.bytesSent, 0), item.totalBytes)
        let sentText = ByteCountFormatter.string(fromByteCount: sentBytes, countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
        let percent = Int((item.progressFraction * 100).rounded())
        return "\(percent)% · \(sentText)/\(totalText)"
    }

    private func chooseBooks() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = BookSyncService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.begin { response in
            guard response == .OK else { return }
            model.uploadBooks(panel.urls)
        }
        #endif
    }
}
