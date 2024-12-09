import Foundation
import GRPC

enum AuthDataSourceError: Error {
    case notLoggedIn
}

protocol AuthDataSource {
    var isLoggedIn: Bool { get }
    var identityHashValue: String? { get }
    var currentConfigID: String { get }
    var currentAuthorization: AuthModel? { get }
    
    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity, completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void)
    func signRequest(_ callOptions: CallOptions) throws -> CallOptions
    func deleteToken() 
}

final class DefaultAuthDataSource: AuthDataSource {
    
    private let storage: AuthStorage
    private let repository: AuthRepository

    var currentConfigID: String {
        repository.configID
    }
    
    var isLoggedIn: Bool {
        storage.read() != nil
    }
    
    var identityHashValue: String? {
        storage.read()?.identityHash
    }
    
    var currentAuthorization: AuthModel? {
        storage.read()
    }

    init(authRepository: AuthRepository, authStorage: AuthStorage) {
        storage = authStorage
        self.repository = authRepository
    }

    func signRequest(_ callOptions: CallOptions) throws -> CallOptions {
        guard let token = storage.read() else {
            throw AuthDataSourceError.notLoggedIn
        }
        var callOptions = callOptions

        callOptions.customMetadata.add(name: "authorization", value: token.accessToken)
        return callOptions
    }
    
    func generateToken(config: SinchSDKConfig.AppConfig,
                       identity: SinchSDKIdentity,
                       completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void) {
       
        if let token = storage.read(),
            token.clientID == config.clientID,
            token.projectID == config.projectID,
            token.region == config.region,
            token.sinchIdentity == identity {
            
            completion(.success((token)))
            return
        }
        
        switch identity {
        case .anonymous:
            generateAnonymousSessionIfNeeded(completion: { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let token):
                    completion(.success((token)))
                }
            })
        case let .selfSigned(userId, secret):
            generateSignedSession(userId: userId, secret: secret, completion: { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let token):
                    completion(.success((token)))
                }
            })
        }
    }

    func generateSignedSession(userId: String, secret: String, completion: @escaping (Result< AuthModel, AuthRepositoryError>) -> Void) {
        
        repository.createSignedToken(userId: userId, secret: secret) { result in
            switch result {
            case .success(let token):
                self.storage.save(token)
                completion(.success((token)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func generateAnonymousSessionIfNeeded(completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void) {
        
        repository.createAnonymouseToken { result in
            switch result {
            case .success(let token):
                self.storage.save(token)
                completion(.success((token)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    func deleteToken() {
        storage.deleteToken()
    }
}

