import Foundation

protocol AuthStorage {
    func read() -> AuthModel?
    func save(_ token: AuthModel)
}

final class DefaultAuthStorage: AuthStorage {
    private let tokenKey = "sinch_sdk_accessToken"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let config: SinchSDKConfig.AppConfig

    init(config: SinchSDKConfig.AppConfig, userDefaults: UserDefaults = .standard) {
        self.config = config
        self.userDefaults = userDefaults
    }

    func read() -> AuthModel? {
        guard let data = userDefaults.data(forKey: tokenKey) else {
            return nil
        }
        return try? decoder.decode(AuthModel.self, from: data)
    }

    func save(_ token: AuthModel) {
        guard let data = try? encoder.encode(token) else {
            return
        }
        userDefaults.set(data, forKey: tokenKey)
    }
}
