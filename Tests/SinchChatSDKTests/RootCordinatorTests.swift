//
//  RootCordinatorTests.swift
//  
//
//  Created by MacBookPro on 6.4.23..
//

import XCTest
@testable import SinchChatSDK
import GRPC

final class MockAuthDataSource: AuthDataSource {
    var isLoggedIn: Bool = false
    
    var identityHashValue: String?
    
    var currentConfigID: String = ""
    
    var generateTokenCompletion: Result<Void, AuthRepositoryError> = .success(())
    var isTokenDeleted = false
    
    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity, completion: @escaping (Result<Void, AuthRepositoryError>) -> Void) {
        isLoggedIn = true
        completion(generateTokenCompletion)
    }
    
    func signRequest(_ callOptions: GRPC.CallOptions) throws -> GRPC.CallOptions {
        return .standardCallOptions
    }
    
    func deleteToken() {
        isLoggedIn = true
    }
}

final class RootCordinatorTests: XCTestCase {
    var rootCordinator: RootCoordinator!
    
    override func setUpWithError() throws {
        rootCordinator = DefaultRootCoordinator(messageDataSource: MessageDataSourceStub(), authDataSource: MockAuthDataSource(), pushPermissionHandler: PushNotificationHandlerStub())
    }

    func testCreatingOfChatViewController() {
        let viewController =  rootCordinator.getRootViewController(uiConfig: .defaultValue, localizationConfig: .defaultValue)
        XCTAssertNotNil(viewController)

    }
    func testCreatingOfMediaViewController() {
        let url = URL(string: "https://www.google.com")!
        let viewController =  rootCordinator.getMediaViewerController(uiConfig: .defaultValue, localizationConfig: .defaultValue, url: url)
        XCTAssertNotNil(viewController)

    }
    func testCreatingOfLocationViewController() {
        let viewController =  rootCordinator.getLocationViewController(uiConfig: .defaultValue, localizationConfig: .defaultValue)
        XCTAssertNotNil(viewController)

    }
}
