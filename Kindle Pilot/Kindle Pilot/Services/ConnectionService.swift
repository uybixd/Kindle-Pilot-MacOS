import Foundation

final class ConnectionService {
    private let keychainStore: KeychainStore
    private let passwordAccount: String

    init(
        keychainStore: KeychainStore,
        passwordAccount: String
    ) {
        self.keychainStore = keychainStore
        self.passwordAccount = passwordAccount
    }

    func makeClient(settings: ConnectionSettings) -> KindleSSHClient {
        KindleSSHClient(settings: settings) { [keychainStore, passwordAccount] in
            try keychainStore.loadPassword(account: passwordAccount)
        }
    }

    func testConnection(settings: ConnectionSettings) async throws -> String {
        let client = makeClient(settings: settings)
        let result = try await client.exec(command: "printf 'Kindle Pilot connected\\n'; uname -a")
        return result.trimmedOutput
    }

    func detectTouchDevice(settings: ConnectionSettings) async throws -> String {
        let client = makeClient(settings: settings)
        let result = try await client.exec(command: "cat /proc/bus/input/devices")

        if let event = TouchDeviceDetector.extractEventDevice(from: result.standardOutput) {
            return event
        }

        throw NSError(
            domain: "KindlePilot.TouchDeviceDetector",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: L("没有识别到 /dev/input/eventX")]
        )
    }
}
