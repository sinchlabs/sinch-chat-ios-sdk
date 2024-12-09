import Foundation
import GRPC

enum InboxDataSourceError: Error {
    case unknown(Error)
    case notLoggedIn
    case noMoreChannels
    case subscriptionIsAlreadyStarted
}

protocol InboxDataSourceDelegate: AnyObject {
    
    func subscriptionError()
}
protocol InboxDataSource {
    
    var delegate: InboxDataSourceDelegate? { get set }

    func getChannels(completion: @escaping (Result<[Sinch_Chat_Sdk_V1alpha2_Channel], InboxDataSourceError>) -> Void)
    func subscribeForChannels(completion: @escaping (Result<Sinch_Chat_Sdk_V1alpha2_Channel, InboxDataSourceError>) -> Void)
    func cancelSubscription()
    func closeChannel()
    func startChannel()
    func cancelCalls()
    func isSubscribed() -> Bool
    func isFirstPage() -> Bool
    
}
final class DefaultInboxDataSource: InboxDataSource {
   
    var authDataSource: AuthDataSource
    var client: APIClient
    
    var getChannelsCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_GetChannelsRequest, Sinch_Chat_Sdk_V1alpha2_GetChannelsResponse>?
    
    weak var delegate: InboxDataSourceDelegate?
    var firstPage: Bool = true
    
    var nextPageToken: String?
    private let pageSize: Int32 = 10
    private var subscription: ServerStreamingCall<Sinch_Chat_Sdk_V1alpha2_SubscribeToChannelsStreamRequest, Sinch_Chat_Sdk_V1alpha2_SubscribeToChannelsStreamResponse>?
    private var options: GetChatViewControllerOptions?

    private let jsonEncoder = JSONEncoder()
    
    init(apiClient: APIClient, authDataSource: AuthDataSource, options: GetChatViewControllerOptions? = nil) {
        self.client = apiClient
        self.authDataSource = authDataSource
        self.options = options
        
    }
    func closeChannel() {
        self.client.closeChannel()
    }
    func startChannel() {
        self.client.startChannel()
    }
    func getChannels(completion: @escaping (Result<[Sinch_Chat_Sdk_V1alpha2_Channel], InboxDataSourceError>) -> Void) {
        if let nextPageToken = nextPageToken {
            if nextPageToken.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    
                    completion(.failure(.noMoreChannels))
                }
                return
            }
        }
        do {
            let service = try getService()
            
            var request = Sinch_Chat_Sdk_V1alpha2_GetChannelsRequest()
            request.pageSize = self.pageSize

            if let nextPageToken = nextPageToken {
                  firstPage = false
                  request.pageToken = nextPageToken
            }
           
            self.getChannelsCall = service.getChannels(request, callOptions: nil)
            
            _ = self.getChannelsCall?.response.always { [weak self] result in
                
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    
                    switch result {
                        
                    case .success(let result):
                        
                        self.nextPageToken = result.nextPageToken
                        completion(.success(result.channels))
                        
                    case .failure(let err):
                        completion(.failure(.unknown(err)))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.notLoggedIn))
            }
        }
    }
    
    func subscribeForChannels(completion: @escaping (Result<Sinch_Chat_Sdk_V1alpha2_Channel, InboxDataSourceError>) -> Void) {
        
        guard subscription == nil else {
            DispatchQueue.main.async {
                
                completion(.failure(.subscriptionIsAlreadyStarted))
            }
            return
        }
        do {
            let service = try getService()
            let request = Sinch_Chat_Sdk_V1alpha2_SubscribeToChannelsStreamRequest()
            
            let subscription = service.subscribeToChannelsStream(request, callOptions: nil) { [weak self] response in
                guard let self = self else {
                    return
                }
                
                DispatchQueue.main.async {
                    
                    completion(.success(response.channel))
                    
                }
            }
            
            self.subscription = subscription
            
            self.subscription?.status.whenComplete({ [weak self] response in
                
                guard let self = self else {
                    return
                }
                debugPrint(response)
                
                switch response {
                    
                case .success(let status):
                    debugPrint(status)
                    
                    if status.code == GRPCStatus.Code(rawValue: 14) {
                        self.subscription = nil
                        self.delegate?.subscriptionError()
                    }
                    
                case .failure(_):
                    break
                }
            })
        } catch {
            DispatchQueue.main.async {
                
                completion(.failure(.notLoggedIn))
            }
        }
    }
    
    func cancelCalls() {
        getChannelsCall?.cancel(promise: nil)
        
    }
    
    func cancelSubscription() {
        nextPageToken = nil
        subscription?.cancel(promise: nil)
        subscription = nil
        firstPage = true
        
    }
    func isSubscribed() -> Bool {
        (subscription != nil)
    }
    func isFirstPage() -> Bool {
        return firstPage
    }
    
    private func getService() throws -> Sinch_Chat_Sdk_V1alpha2_SdkServiceNIOClient {
        try Sinch_Chat_Sdk_V1alpha2_SdkServiceNIOClient(channel: client.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
    
}
