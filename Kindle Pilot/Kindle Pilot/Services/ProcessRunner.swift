import Foundation

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

final class ProcessRunner {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        standardInputFileURL: URL? = nil,
        standardOutputFileURL: URL? = nil,
        standardInputProgress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> SSHCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment

            var stdoutPipe: Pipe?
            var stdoutFile: FileHandle?
            var stdinPipe: Pipe?
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            let stdinFile: FileHandle?
            do {
                if let standardOutputFileURL {
                    let directory = standardOutputFileURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    if !FileManager.default.fileExists(atPath: standardOutputFileURL.path) {
                        FileManager.default.createFile(atPath: standardOutputFileURL.path, contents: nil)
                    }
                    let file = try FileHandle(forWritingTo: standardOutputFileURL)
                    try file.truncate(atOffset: 0)
                    stdoutFile = file
                    process.standardOutput = file
                } else {
                    let pipe = Pipe()
                    stdoutPipe = pipe
                    process.standardOutput = pipe
                }

                if let standardInputFileURL {
                    if standardInputProgress != nil {
                        let pipe = Pipe()
                        stdinPipe = pipe
                        stdinFile = nil
                        process.standardInput = pipe
                    } else {
                        stdinFile = try FileHandle(forReadingFrom: standardInputFileURL)
                        process.standardInput = stdinFile
                    }
                } else {
                    let stdinPipe = Pipe()
                    process.standardInput = stdinPipe
                    try? stdinPipe.fileHandleForWriting.close()
                    stdinFile = nil
                }
            } catch {
                continuation.resume(
                    throwing: ProcessRunnerError.launchFailed(error.localizedDescription)
                )
                return
            }

            let stdoutReader = stdoutPipe?.fileHandleForReading
            let stdoutWriter = stdoutFile
            let stdinWriter = stdinPipe?.fileHandleForWriting
            let completion = ProcessRunCompletion(continuation: continuation)

            process.terminationHandler = { finishedProcess in
                let stdoutData = stdoutReader?.readDataToEndOfFile() ?? Data()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                try? stdinFile?.close()
                try? stdinWriter?.close()
                try? stdoutWriter?.close()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let result = SSHCommandResult(
                    exitCode: finishedProcess.terminationStatus,
                    standardOutput: stdout,
                    standardError: stderr
                )

                if let streamError = completion.inputStreamError, result.exitCode == 0 {
                    completion.complete(.failure(streamError))
                } else {
                    completion.complete(.success(result))
                }
            }

            do {
                try process.run()
            } catch {
                try? stdinFile?.close()
                try? stdinWriter?.close()
                try? stdoutFile?.close()
                completion.complete(.failure(ProcessRunnerError.launchFailed(error.localizedDescription)))
                return
            }

            if let standardInputFileURL,
               let standardInputProgress,
               let stdinWriter {
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try Self.streamFile(
                            at: standardInputFileURL,
                            to: stdinWriter,
                            progress: standardInputProgress
                        )
                    } catch {
                        completion.setInputStreamError(error)

                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }
            }
        }
    }

    private static func streamFile(
        at fileURL: URL,
        to output: FileHandle,
        progress: (Int64, Int64) -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? input.close()
            try? output.close()
        }

        let totalBytes = try fileSize(at: fileURL)
        var sentBytes: Int64 = 0
        progress(sentBytes, totalBytes)

        while true {
            guard let chunk = try input.read(upToCount: 1024 * 1024),
                  !chunk.isEmpty else {
                break
            }

            try output.write(contentsOf: chunk)
            sentBytes += Int64(chunk.count)
            progress(sentBytes, totalBytes)
        }
    }

    private static func fileSize(at fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

nonisolated private final class ProcessRunCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private var streamError: Error?
    private let continuation: CheckedContinuation<SSHCommandResult, Error>

    init(continuation: CheckedContinuation<SSHCommandResult, Error>) {
        self.continuation = continuation
    }

    var inputStreamError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return streamError
    }

    func setInputStreamError(_ error: Error) {
        lock.lock()
        streamError = error
        lock.unlock()
    }

    func complete(_ result: Result<SSHCommandResult, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()

        switch result {
        case .success(let commandResult):
            continuation.resume(returning: commandResult)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
