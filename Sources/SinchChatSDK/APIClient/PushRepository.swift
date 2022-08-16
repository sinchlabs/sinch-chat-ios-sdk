import Foundation

enum PushRepositoryError: Error {
    // Report this error to us.
    case internalError
}

protocol PushRepository {
    func sendDeviceToken(token: String, completion: @escaping (Result<Void, Error>) -> Void)
    func replyToMessageWithTextChoice(choice: ChoiceText, completion: @escaping (Result<Void, Error>) -> Void) 
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
            guard let client = DefaultAPIClient(region: region) else {
                completion(.failure(PushRepositoryError.internalError))
                return
            }
            let service = try getService(apiClient: client)

            var request = Sinch_Chat_Sdk_V1alpha2_SubscribeToPushRequest()
            
            switch SinchChatSDK.shared.options?.pushNotificationsMode {
            case .off:
                completion(.success(()))
                return
            case .sandbox:
                request.platform = Sinch_Chat_Sdk_V1alpha2_PushPlatform.iosSandbox
            case .prod, nil:
                request.platform = Sinch_Chat_Sdk_V1alpha2_PushPlatform.ios
            }
            request.token = token
            
//            request.subscriptionToken = token
//            request.configID = authDataSource.currentConfigID
                        
            _ = service.subscribeToPush(request).response.always { result in
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
    func replyToMessageWithTextChoice(choice: ChoiceText, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
//        do {
//            guard let client = DefaultPushAPIClient(region: region) else {
//                completion(.failure(PushRepositoryError.internalError))
//                return
//            }
//            let service = try getPushService(apiClient: client)
//            var request = Sinch_Push_Sdk_V1beta1_ReplyRequest()
//            request.messageID = choice.entryID
//
//            service.reply(request)
//
//        } catch {
//            completion(.failure(error))
//        }
    }

    // MARK: Private
    
    private func getService(apiClient: APIClient) throws -> Sinch_Chat_Sdk_V1alpha2_SdkServiceClient {
        try Sinch_Chat_Sdk_V1alpha2_SdkServiceClient(channel: apiClient.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
        
    private func getPushService(apiClient: PushAPIClient) throws -> Sinch_Push_Sdk_V1beta1_SdkServiceClient {
        try Sinch_Push_Sdk_V1beta1_SdkServiceClient(channel: apiClient.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
}
