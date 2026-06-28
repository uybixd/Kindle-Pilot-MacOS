import Foundation

enum SSHAuthenticationMethod: String, CaseIterable, Codable, Identifiable {
    case password
    case privateKey
    case sshAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password:
            return L("密码")
        case .privateKey:
            return L("私钥")
        case .sshAgent:
            return "SSH Agent"
        }
    }
}

struct ConnectionSettings: Codable, Equatable {
    var host: String
    var port: Int
    var username: String
    var authenticationMethod: SSHAuthenticationMethod
    var privateKeyPath: String
    var eventDevice: String

    static let defaults = ConnectionSettings(
        host: "192.168.31.204",
        port: 22,
        username: "root",
        authenticationMethod: .password,
        privateKeyPath: "",
        eventDevice: ""
    )

    var target: String {
        "\(username)@\(host)"
    }

    var normalizedEventDevice: String? {
        let trimmed = eventDevice.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed.hasPrefix("/dev/input/") {
            return String(trimmed.dropFirst("/dev/input/".count))
        }
        return trimmed
    }
}

enum PageTurnDirection: Hashable {
    case previous
    case next

    var remoteEventName: String {
        switch self {
        case .previous:
            return "prev"
        case .next:
            return "next"
        }
    }

    var logTitle: String {
        switch self {
        case .previous:
            return L("上一页")
        case .next:
            return L("下一页")
        }
    }
}

struct SSHCommandResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
