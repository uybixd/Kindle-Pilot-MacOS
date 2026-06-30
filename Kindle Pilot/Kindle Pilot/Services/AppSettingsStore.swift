import Foundation

final class AppSettingsStore {
    private let connectionKey = "connectionSettings"
    private let clippingsSortOrderKey = "clippingsSortOrder"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ConnectionSettings {
        guard let data = defaults.data(forKey: connectionKey) else {
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
        defaults.set(data, forKey: connectionKey)
    }

    func loadClippingsSortOrder() -> ClippingsSortOrder {
        guard let rawValue = defaults.string(forKey: clippingsSortOrderKey) else {
            return .addedAt
        }
        return ClippingsSortOrder(rawValue: rawValue) ?? .addedAt
    }

    func saveClippingsSortOrder(_ sortOrder: ClippingsSortOrder) {
        defaults.set(sortOrder.rawValue, forKey: clippingsSortOrderKey)
    }
}
