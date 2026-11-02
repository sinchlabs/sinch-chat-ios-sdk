import Foundation
import SwiftProtobuf

enum PushRepositoryError: Error, Sendable {
    case internalError
}

protocol PushRepository: Sendable {
    /// - Parameter deviceInfo: sent with the token for relay routing. `nil` subscribes without device fields.
    /// - Returns: The subscriber id the server sent with the Subscribe response, when it sent one.
    @discardableResult
    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String?
    func unsubscribe(_ currentDeviceToken: String) async throws

    func sendDeviceToken(token: String,
                         deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void)
    func unsubscribe(_ currentDeviceToken: String,
                     _ completion: @escaping @Sendable (Result<Void, Error>) -> Void)
}

final class DefaultPushRepository: PushRepository, @unchecked Sendable {

    /// The push service methods, over the native gRPC host with the gRPC-web framing.
    enum Path {
        static let subscribe = "sinch.push.sdk.v1beta1.SdkService/Subscribe"
        static let unsubscribe = "sinch.push.sdk.v1beta1.SdkService/Unsubscribe"
    }

    /// A subscribe waits at most this long, so a login does not hang on the network.
    static let callTimeout: Duration = .seconds(5)

    private let authDataSource: AuthDataSource
    private let client: PushAPIClient?
    private let metadata: StandardMetadata

    init(region: Region,
         authDataSource: AuthDataSource,
         client: PushAPIClient? = nil,
         metadata: StandardMetadata = .init()) {
        self.authDataSource = authDataSource
        self.client = client ?? DefaultPushAPIClient(region: region)
        self.metadata = metadata
    }

    // MARK: - Async API

    @discardableResult
    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String? {
        guard let client = self.client?.grpcWebClient else {
            throw PushRepositoryError.internalError
        }

        let request = Self.subscribeRequest(token: token,
                                            config: authDataSource.currentConfigID,
                                            deviceInfo: deviceInfo)
        let headers = metadata.headers(token: try? authDataSource.currentAccessToken())

        do {
            let response: Sinch_Push_Sdk_V1beta1_SubscribeResponse = try await client.unary(
                path: Path.subscribe,
                request: request,
                metadata: headers,
                timeout: Self.callTimeout)
            return response.hasSubscriberID ? response.subscriberID : nil
        } catch _ as AuthDataSourceError {
            throw PushRepositoryError.internalError
        } catch {
            throw error
        }
    }

    /// Omits empty optional fields, and all device fields when the installation id is unavailable.
    static func subscribeRequest(token: String,
                                 config: String,
                                 deviceInfo: DeviceInfo?) -> Sinch_Push_Sdk_V1beta1_SubscribeRequest {
        Sinch_Push_Sdk_V1beta1_SubscribeRequest.with {
            if !token.isEmpty {
                $0.token = token
            }
            if !config.isEmpty {
                $0.config = config
            }
            guard let info = deviceInfo?.subscribable else { return }
            $0.installationID = info.installationId
            // Subscribe uses the push platform enum, not the WebSocket enum.
            $0.platform = .ios
            if !info.osVersion.isEmpty {
                $0.osVersion = info.osVersion
            }
            if !info.sdkVersion.isEmpty {
                $0.sdkVersion = info.sdkVersion
            }
            if !info.bundleId.isEmpty {
                $0.bundleID = info.bundleId
            }
            $0.backgroundService = info.backgroundService
        }
    }

    func unsubscribe(_ currentDeviceToken: String) async throws {
        guard let client = self.client?.grpcWebClient else {
            throw PushRepositoryError.internalError
        }

        let request = Sinch_Push_Sdk_V1beta1_UnsubscribeRequest.with {
            // The fields are optional on the wire; an empty value stays absent.
            let config = authDataSource.currentConfigID
            if !config.isEmpty {
                $0.config = config
            }
            if !currentDeviceToken.isEmpty {
                $0.token = currentDeviceToken
            }
        }

        let headers = metadata.headers(token: try? authDataSource.currentAccessToken())

        do {
            let _: SwiftProtobuf.Google_Protobuf_Empty = try await client.unary(
                path: Path.unsubscribe,
                request: request,
                metadata: headers,
                timeout: Self.callTimeout)
        } catch _ as AuthDataSourceError {
            throw PushRepositoryError.internalError
        } catch {
            // Non-auth transport errors are logged and swallowed.
            Logger.verbose("Unsubscribe error: \(error.localizedDescription)")
        }
    }

    // Each completion task captures `self`, which keeps the repository alive until it is delivered.
    func sendDeviceToken(token: String,
                         deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Task {
            do {
                _ = try await self.sendDeviceToken(token: token, deviceInfo: deviceInfo)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func unsubscribe(_ currentDeviceToken: String,
                     _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await self.unsubscribe(currentDeviceToken)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
