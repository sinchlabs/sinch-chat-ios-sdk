import Foundation

enum PushRepositoryError: Error {
    // Report this error to us.
    case internalError
}

protocol PushRepository {
    func sendDeviceToken(token: String, completion: @escaping (Result<Void, Error>) -> Void)
    func unsubscribe(_ completion: @escaping (Result<Void, Error>) -> Void)
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
            guard let client = DefaultPushAPIClient(region: region) else {
                completion(.failure(PushRepositoryError.internalError))
                return
            }
            let service = try getPushService(apiClient: client)

            var request = Sinch_Push_Sdk_V1beta1_SubscribeRequest()
            
            request.token = token
            request.config = authDataSource.currentConfigID
            
            _ = service.subscribe(request).response.always { result in
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
    
    func unsubscribe(_ completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard let client = DefaultPushAPIClient(region: region) else {
                completion(.failure(PushRepositoryError.internalError))
                return
            }
            let service = try getPushService(apiClient: client)

            var request = Sinch_Push_Sdk_V1beta1_UnsubscribeRequest()
            
            request.config = authDataSource.currentConfigID
            
            _ = service.unsubscribe(request).response.always { result in
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
//
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
        
    private func getPushService(apiClient: PushAPIClient) throws -> Sinch_Push_Sdk_V1beta1_SdkServiceNIOClient {
        try Sinch_Push_Sdk_V1beta1_SdkServiceNIOClient(channel: apiClient.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
}
