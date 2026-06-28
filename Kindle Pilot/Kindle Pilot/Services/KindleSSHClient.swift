import Foundation

enum KindleSSHClientError: Error, LocalizedError {
    case missingPassword
    case missingPrivateKeyPath
    case commandFailed(command: String, exitCode: Int32, output: String, error: String)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return L("密码认证需要先保存密码")
        case .missingPrivateKeyPath:
            return L("私钥认证需要填写私钥路径")
        case .commandFailed(_, let exitCode, let output, let error):
            let summary = exitCode == 255
                ? L("SSH 连接失败，请确认 Kindle 在线、IP/认证正确。")
                : LF("命令失败(%d)", exitCode)
            let details = Self.cleanedFailureDetails(output: output, error: error)
            return details.isEmpty ? summary : "\(summary)\n\(details)"
        }
    }

    private static func cleanedFailureDetails(output: String, error: String) -> String {
        let lines = [output, error]
            .flatMap { value in
                value
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty }
            .filter { !isOpenSSHNoise($0) }

        let details = lines.joined(separator: "\n")
        guard details.count > 600 else {
            return details
        }
        return "\(details.prefix(600))..."
    }

    private static func isOpenSSHNoise(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "* "))

        return normalized.hasPrefix("WARNING: connection is not using a post-quantum key exchange algorithm")
            || normalized.hasPrefix("This session may be vulnerable")
            || normalized.hasPrefix("The server may need to be upgraded")
    }
}

final class KindleSSHClient {
    private let settings: ConnectionSettings
    private let passwordProvider: () throws -> String?
    private let processRunner: ProcessRunner

    init(
        settings: ConnectionSettings,
        passwordProvider: @escaping () throws -> String?,
        processRunner: ProcessRunner = ProcessRunner()
    ) {
        self.settings = settings
        self.passwordProvider = passwordProvider
        self.processRunner = processRunner
    }

    func exec(command: String) async throws -> SSHCommandResult {
        let environment = try sshEnvironment()
        defer {
            try? environment.cleanup()
        }

        let result = try await processRunner.run(
            executablePath: "/usr/bin/ssh",
            arguments: sshArguments(remoteCommand: command),
            environment: environment.values
        )
        try validate(result, command: command)
        return result
    }

    func download(remotePath: String, to localURL: URL) async throws -> SSHCommandResult {
        let environment = try sshEnvironment()
        defer {
            try? environment.cleanup()
        }

        let command = "cat \(shellQuote(remotePath))"
        let tempURL = localURL
            .deletingLastPathComponent()
            .appendingPathComponent(".kindle-pilot-download-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let result = try await processRunner.run(
            executablePath: "/usr/bin/ssh",
            arguments: sshArguments(remoteCommand: command),
            environment: environment.values,
            standardOutputFileURL: tempURL
        )
        try validate(result, command: "ssh download \(remotePath)")

        let directory = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return result
    }

    func upload(
        localURL: URL,
        to remotePath: String,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> SSHCommandResult {
        let environment = try sshEnvironment()
        defer {
            try? environment.cleanup()
        }

        let tempRemotePath = temporaryRemotePath(for: remotePath)
        let command = """
        set -e; \
        cat > \(shellQuote(tempRemotePath)); \
        mv -f \(shellQuote(tempRemotePath)) \(shellQuote(remotePath))
        """
        let result = try await processRunner.run(
            executablePath: "/usr/bin/ssh",
            arguments: sshArguments(remoteCommand: command),
            environment: environment.values,
            standardInputFileURL: localURL,
            standardInputProgress: progress
        )
        try validate(result, command: "ssh upload \(localURL.lastPathComponent)")
        return result
    }

    private func validate(_ result: SSHCommandResult, command: String) throws {
        guard result.exitCode == 0 else {
            throw KindleSSHClientError.commandFailed(
                command: command,
                exitCode: result.exitCode,
                output: result.standardOutput,
                error: result.standardError
            )
        }
    }

    private func sshArguments(remoteCommand: String?) -> [String] {
        var arguments = commonSSHOptions(portFlag: "-p")

        switch settings.authenticationMethod {
        case .password:
            arguments += [
                "-o", "BatchMode=no",
                "-o", "NumberOfPasswordPrompts=1",
                "-o", "PubkeyAuthentication=no",
                "-o", "PasswordAuthentication=yes",
                "-o", "KbdInteractiveAuthentication=yes",
                "-o", "PreferredAuthentications=password,keyboard-interactive"
            ]
        case .privateKey:
            arguments += [
                "-i", settings.privateKeyPath,
                "-o", "BatchMode=yes"
            ]
        case .sshAgent:
            arguments += [
                "-o", "BatchMode=yes"
            ]
        }

        arguments.append(settings.target)
        if let remoteCommand {
            arguments.append(remoteCommand)
        }
        return arguments
    }

    private func scpArguments() -> [String] {
        var arguments = ["-O"] + commonSSHOptions(portFlag: "-P")

        switch settings.authenticationMethod {
        case .password:
            arguments += [
                "-o", "BatchMode=no",
                "-o", "NumberOfPasswordPrompts=1",
                "-o", "PubkeyAuthentication=no",
                "-o", "PasswordAuthentication=yes",
                "-o", "KbdInteractiveAuthentication=yes",
                "-o", "PreferredAuthentications=password,keyboard-interactive"
            ]
        case .privateKey:
            arguments += [
                "-i", settings.privateKeyPath,
                "-o", "BatchMode=yes"
            ]
        case .sshAgent:
            arguments += [
                "-o", "BatchMode=yes"
            ]
        }

        return arguments
    }

    private func commonSSHOptions(portFlag: String) -> [String] {
        [
            portFlag, String(settings.port),
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=10",
            "-o", "UserKnownHostsFile=\(knownHostsPath())",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
    }

    private func sshEnvironment() throws -> SSHProcessEnvironment {
        switch settings.authenticationMethod {
        case .password:
            guard let password = try passwordProvider() else {
                throw KindleSSHClientError.missingPassword
            }
            return SSHProcessEnvironment(password: password)
        case .privateKey:
            guard !settings.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KindleSSHClientError.missingPrivateKeyPath
            }
            return SSHProcessEnvironment(values: [:])
        case .sshAgent:
            return SSHProcessEnvironment(values: [:])
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func knownHostsPath() -> String {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = baseURL.appendingPathComponent("Kindle Pilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("known_hosts").path
    }

    private func temporaryRemotePath(for remotePath: String) -> String {
        let url = URL(fileURLWithPath: remotePath)
        let directory = remotePath.hasPrefix("/")
            ? url.deletingLastPathComponent().path
            : "/mnt/us/documents"
        let ext = url.pathExtension.isEmpty ? "upload" : url.pathExtension
        return "\(directory)/.kindle-pilot-upload-\(UUID().uuidString).\(ext)"
    }
}

private struct SSHProcessEnvironment {
    let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    init(password: String) {
        let askpassPath = Self.askpassHelperPath()
        self.values = [
            "SSH_ASKPASS": askpassPath,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "kindle-pilot",
            "KINDLE_PILOT_ASKPASS": "1",
            "KINDLE_PILOT_PASSWORD": password
        ]
    }

    func cleanup() throws {
    }

    private static func askpassHelperPath() -> String {
        if let path = Bundle.main.url(forResource: "KindleAskpass", withExtension: nil)?.path {
            return path
        }

        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("KindleAskpass")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }

        return Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }
}
