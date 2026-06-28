import Foundation

final class AppSettingsStore {
    private let key = "connectionSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ConnectionSettings {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(ConnectionSettings.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ settings: ConnectionSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
