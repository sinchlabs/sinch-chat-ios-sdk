import Foundation

/// Why a socket configuration could not be derived from the identity.
enum RelayConfigurationError: Error, Equatable, CustomStringConvertible {
    case missingUserID
    case missingAppID

    var description: String {
        switch self {
        case .missingUserID: return "access token has no user id (uuid claim)"
        case .missingAppID: return "access token has no app id (appId / app_id claim)"
        }
    }
}

/// The access-token claims the relay handshake needs. Wrong-typed or empty values count as absent.
struct RelayJWTClaims: Equatable {
    var appID: String?
    var projectID: String?
    var userID: String?

    init(appID: String? = nil, projectID: String? = nil, userID: String? = nil) {
        self.appID = appID
        self.projectID = projectID
        self.userID = userID
    }

    /// Accepts `appId`/`app_id`, `projectId`/`project_id` and `uuid`. `nil` when the token is not a decodable JWT.
    init?(token: String) {
        guard let payload = try? JWTDecoder.decode(jwtToken: token) else { return nil }
        func string(_ keys: String...) -> String? {
            for key in keys {
                if let value = payload[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }
        self.init(appID: string("appId", "app_id"),
                  projectID: string("projectId", "project_id"),
                  userID: string("uuid"))
    }
}

extension SocketConfiguration {
    /// The relay configuration for an authorized identity. The app and user ids are required from the token.
    static func relay(url: URL, auth: AuthModel, config: SinchSDKConfig.AppConfig)
        -> Result<SocketConfiguration, RelayConfigurationError> {
        guard let claims = RelayJWTClaims(token: auth.accessToken), let userID = claims.userID else {
            return .failure(.missingUserID)
        }
        guard let appID = claims.appID else { return .failure(.missingAppID) }
        return .success(SocketConfiguration(url: url.absoluteString,
                                            authToken: auth.accessToken,
                                            projectID: claims.projectID ?? config.projectID,
                                            appID: appID,
                                            userID: userID,
                                            displayNotifications: .always))
    }

    /// The owner of the outbox and cursor: `appID|projectID|userID`.
    var sessionOwnerKey: String { "\(appID)|\(projectID)|\(userID)" }

    /// Whether `other` is the same session, ignoring the token.
    func isSameSession(as other: SocketConfiguration) -> Bool {
        url == other.url && userID == other.userID && appID == other.appID && projectID == other.projectID
    }
}
