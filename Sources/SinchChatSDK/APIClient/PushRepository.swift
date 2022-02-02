import Foundation

protocol PushRepository {
    func sendDeviceToken(token: String, completion: @escaping (Result<Void, Error>) -> Void)
}

final class DefaultPushRepository: PushRepository {
    private let authDataSource: AuthDataSource
    private let region: Region

    init(region: Region, authDataSource: AuthDataSource) {
        self.region = region
        self.authDataSource = authDataSource
    }

    func sendDeviceToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let client = DefaultAPIClient(region: region)
            let service = try getService(apiClient: client)

            var request = Sinch_Chat_Sdk_V1alpha2_SubscribeToPushRequest()
            switch SinchChatSDK.shared.options?.pushNotificationsMode {
            case .off:
                completion(.success(()))
                return
            case .sandbox:
                request.platform = Sinch_Push_V1alpha1_Platform.iosSandbox
            case .prod, nil:
                request.platform = Sinch_Push_V1alpha1_Platform.ios
            }
            request.token = token

            _ = service.subscribeToPush(request, callOptions: nil).response.always { result in
                client.closeChannel()

                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: Private

    private func getService(apiClient: APIClient) throws -> Sinch_Chat_Sdk_V1alpha2_SdkServiceClient {
        try Sinch_Chat_Sdk_V1alpha2_SdkServiceClient(channel: apiClient.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
        
    }
}
