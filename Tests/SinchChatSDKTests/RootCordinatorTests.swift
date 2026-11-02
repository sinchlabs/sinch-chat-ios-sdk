//
//  RootCordinatorTests.swift
//  
//
//  Created by MacBookPro on 6.4.23..
//

import XCTest
@testable import SinchChatSDK
import GRPCCore

final class MockTokenProvider: ChatTokenProvider, @unchecked Sendable {
    var currentAuthorization: AuthModel?

    var isLoggedIn: Bool = false

    func currentAccessToken() throws -> String {
        "token"
    }
}

@MainActor
final class RootCordinatorTests: XCTestCase {
    var rootCordinator: RootCoordinator!
    
    override func setUpWithError() throws {
        rootCordinator = DefaultRootCoordinator(messageDataSource: MessageDataSourceStub(), tokenProvider: MockTokenProvider(), pushPermissionHandler: PushNotificationHandlerStub())
    }

    func testCreatingOfChatViewController() {
        let viewController =  rootCordinator.getRootViewController(uiConfig: .defaultValue, localizationConfig: .defaultValue, sendDocumentAsText: false)
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
