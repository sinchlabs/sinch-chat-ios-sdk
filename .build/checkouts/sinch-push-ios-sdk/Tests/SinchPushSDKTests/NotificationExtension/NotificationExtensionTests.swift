import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// `SinchPushNotificationExtension.didReceive`, over a temporary container and a fake session.
final class NotificationExtensionTests: XCTestCase {

    private var container: ReportContainer!
    private var session: FakeReportUploadSession!
    private var uploader: BackgroundReportUploader!
    private let baseURL = URL(string: "https://grpc.sinch-push.prod.sinch.com")!

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
        session = FakeReportUploadSession()
        let fake = session!
        uploader = BackgroundReportUploader(identifier: BackgroundReportUploader.makeExtensionIdentifier(),
                                            container: container, makeSession: { _ in fake })
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func sinchPush(message: String = "m-1", subscriber: String = "s-1") -> [AnyHashable: Any] {
        ["aps": ["alert": "hi", "mutable-content": 1],
         "sinch.push.message_id": message, "sinch.push.subscriber_id": subscriber]
    }

    private func mirrorCredentials() {
        SharedReportCredentialsStore(container: container).write(
            SharedReportCredentials(accessToken: "jwt", reportBaseURL: baseURL, userId: "u-1", appId: "cfg"))
    }

    private func didReceive(_ userInfo: [AnyHashable: Any]) -> Bool {
        let uploader = uploader!
        return SinchPushNotificationExtension.didReceive(userInfo: userInfo, container: container) { _ in uploader }
    }

    func testASinchPushIsHandedToTheUpload() throws {
        mirrorCredentials()

        XCTAssertTrue(didReceive(sinchPush()))

        let started = try XCTUnwrap(session.started.first)
        XCTAssertEqual(started.body, GRPCWebReportEvents.body(for: [ReportedDelivery(messageID: "m-1", subscriberID: "s-1")]))
        XCTAssertEqual(started.request.value(forHTTPHeaderField: "authorization"), "jwt")
        XCTAssertEqual(started.request.url?.host, "grpc.sinch-push.prod.sinch.com")
    }

    func testAPushThatIsNotFromSinchIsNotHandled() {
        mirrorCredentials()

        XCTAssertFalse(didReceive(["aps": ["alert": "hi"]]))
        XCTAssertFalse(didReceive(["sinch.push.message_id": "m-1"]), "no subscriber")
        XCTAssertTrue(session.started.isEmpty)
    }

    func testWithoutAMirroredSessionNothingIsHandled() {
        XCTAssertFalse(didReceive(sinchPush()))
        XCTAssertTrue(session.started.isEmpty)
    }

    func testWithoutAnAppGroupNothingIsHandled() {
        let unshared = makeTestContainer(appGroup: nil)
        SharedReportCredentialsStore(container: unshared).write(
            SharedReportCredentials(accessToken: "jwt", reportBaseURL: baseURL, userId: nil, appId: "cfg"))
        let uploader = uploader!

        XCTAssertFalse(SinchPushNotificationExtension.didReceive(userInfo: sinchPush(), container: unshared) { _ in uploader })
    }

    func testADeliveryReportedBeforeIsNotUploadedAgain() {
        mirrorCredentials()
        SentReportMarkerStore(container: container).record([ReportedDelivery(messageID: "m-1", subscriberID: "s-1")])

        XCTAssertTrue(didReceive(sinchPush()))
        XCTAssertTrue(session.started.isEmpty)
    }

    private func jwt(exp: TimeInterval) -> String {
        func encode(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [encode(#"{"alg":"none"}"#), encode(#"{"exp":\#(Int(exp))}"#), "sig"].joined(separator: ".")
    }

    private func mirrorCredentials(token: String) {
        SharedReportCredentialsStore(container: container).write(
            SharedReportCredentials(accessToken: token, reportBaseURL: baseURL, userId: "u-1", appId: "cfg"))
    }

    func testAnExpiredTokenIsNotUploadedAndTheDeliveryIsLeftToTheApp() {
        mirrorCredentials(token: jwt(exp: Date().timeIntervalSince1970 - 10))

        XCTAssertTrue(didReceive(sinchPush()))

        XCTAssertTrue(session.started.isEmpty)
        XCTAssertEqual(container.takePendingDeliveries().map(\.messageId), ["m-1"])
    }

    func testATokenThatExpiresWithinTheLeewayIsNotUploadedEither() {
        mirrorCredentials(token: jwt(exp: Date().timeIntervalSince1970 + 30))

        XCTAssertTrue(didReceive(sinchPush()))

        XCTAssertTrue(session.started.isEmpty)
        XCTAssertEqual(container.takePendingDeliveries().count, 1)
    }

    func testATokenThatIsValidForAWhileIsUploaded() {
        mirrorCredentials(token: jwt(exp: Date().timeIntervalSince1970 + 3600))

        XCTAssertTrue(didReceive(sinchPush()))

        XCTAssertEqual(session.started.count, 1)
        XCTAssertEqual(container.takePendingDeliveries(), [])
    }

    func testAnExpiredTokenOfADeliveryReportedBeforeLeavesNothingPending() {
        mirrorCredentials(token: jwt(exp: Date().timeIntervalSince1970 - 10))
        SentReportMarkerStore(container: container).record([ReportedDelivery(messageID: "m-1", subscriberID: "s-1")])

        XCTAssertTrue(didReceive(sinchPush()))

        XCTAssertEqual(container.takePendingDeliveries(), [])
    }

    func testTheUploadFailureOfAPushIsLeftToTheApp() throws {
        mirrorCredentials()
        XCTAssertTrue(didReceive(sinchPush()))
        let started = try XCTUnwrap(session.started.first)

        uploader.uploadFinished(taskDescription: started.taskDescription, httpStatus: 401, headerGrpcStatus: nil,
                                body: Data(), error: nil)

        XCTAssertEqual(container.takePendingDeliveries().map(\.messageId), ["m-1"])
    }

    func testAnUploadThatCannotWriteItsFileIsNotClaimed() throws {
        mirrorCredentials()
        // A regular file where the directory should be: the upload file cannot be written.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let broken = BackgroundReportUploader(identifier: "x",
                                              container: ReportContainer(appGroup: "g", directory: blocker),
                                              makeSession: { _ in FakeReportUploadSession() })

        XCTAssertFalse(SinchPushNotificationExtension.didReceive(userInfo: sinchPush(), container: container) { _ in broken })
    }
}

/// The mirror the app keeps for the extension.
final class ReportCredentialsMirrorTests: XCTestCase {

    private var container: ReportContainer!
    private let secret = "THE-HMAC-SECRET"

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func jwt(uuid: String) -> String {
        func encode(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [encode(#"{"alg":"none"}"#), encode(#"{"uuid":"\#(uuid)"}"#), "sig"].joined(separator: ".")
    }

    private func token(region: Region = .EU1) -> AuthModel {
        AuthModel(accessToken: jwt(uuid: "user-1"), sinchIdentity: .selfSigned(userId: "user-1", secret: secret),
                  clientID: "client", projectID: "project", configID: "config", region: region)
    }

    private var mirrored: SharedReportCredentials? { SharedReportCredentialsStore(container: container).read() }

    private let defaults = UserDefaults(suiteName: "mirror-tests-\(UUID().uuidString)")!

    private func mirror() -> ReportCredentialsMirror {
        ReportCredentialsMirror(container: container, defaults: defaults)
    }

    private func storage(_ base: MirrorBackingAuthStorage = MirrorBackingAuthStorage()) -> MirroringAuthStorage {
        MirroringAuthStorage(base: base, mirror: mirror())
    }

    func testSavingATokenMirrorsItForTheExtension() throws {
        let saved = token()

        storage().save(saved)

        let credentials = try XCTUnwrap(mirrored)
        XCTAssertEqual(credentials.accessToken, saved.accessToken)
        XCTAssertEqual(credentials.reportBaseURL.absoluteString, "https://grpc.sinch-push.prod.sinch.com")
        XCTAssertEqual(credentials.userId, "user-1")
        XCTAssertEqual(credentials.appId, "config")
    }

    func testARefreshedTokenReplacesTheMirroredOne() throws {
        let storage = storage()
        storage.save(token())
        let refreshed = AuthModel(accessToken: jwt(uuid: "user-1") + "x", sinchIdentity: token().sinchIdentity,
                                  clientID: "client", projectID: "project", configID: "config", region: .EU1)

        storage.save(refreshed)

        XCTAssertEqual(mirrored?.accessToken, refreshed.accessToken)
    }

    func testTheMirrorHoldsNoSecret() throws {
        storage().save(token())

        let url = try XCTUnwrap(container.directory).appendingPathComponent("report-credentials.json")
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("selfSigned"))
    }

    func testDeletingTheTokenClearsTheMirror() {
        let storage = storage()
        storage.save(token())

        storage.deleteToken()

        XCTAssertNil(mirrored)
        XCTAssertNil(storage.read())
    }

    func testTheTokenIsStoredInTheWrappedStorageAsWell() {
        let base = MirrorBackingAuthStorage()
        let saved = token()

        storage(base).save(saved)

        XCTAssertEqual(base.read()?.accessToken, saved.accessToken)
        XCTAssertEqual(base.read()?.sinchIdentity, saved.sinchIdentity)
    }

    func testNothingIsMirroredWithoutAnAppGroup() {
        container.appGroup = nil

        storage().save(token())

        container.appGroup = "group.test"
        XCTAssertNil(mirrored)
    }

    func testAfterClearingATokenSavedLateIsNotMirrored() {
        let storage = storage()
        storage.save(token())
        storage.deleteToken()

        storage.save(token())

        XCTAssertNil(mirrored, "a refresh that was in flight when the identity was removed")
    }

    func testResumingMirrorsAgain() {
        let storage = storage()
        storage.deleteToken()

        mirror().resume()
        storage.save(token())

        XCTAssertNotNil(mirrored)
    }

    func testTheMirrorIsOnBeforeAnythingWasCleared() {
        storage().save(token())

        XCTAssertNotNil(mirrored)
    }

    func testClearingDeletesTheFileOfTheLastAppGroupWhenNoneIsSetNow() throws {
        storage().save(token())
        XCTAssertNotNil(mirrored)

        container.appGroup = nil
        mirror().clear()

        container.appGroup = "group.test"
        XCTAssertNil(mirrored)
    }

    func testClearingDeletesTheFileOfTheOldGroupWhenTheGroupChanged() {
        let old = makeTestContainer(appGroup: "group.old")
        let oldMirror = ReportCredentialsMirror(container: old, defaults: defaults)
        oldMirror.update(from: token())
        XCTAssertNotNil(SharedReportCredentialsStore(container: old).read())

        let current = ReportContainer(appGroup: "group.new", directory: old.directory?.deletingLastPathComponent())
        ReportCredentialsMirror(container: current, defaults: defaults).clear()

        XCTAssertNil(SharedReportCredentialsStore(container: old).read())
        if let directory = old.directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testTheCustomRegionKeepsItsPortAndScheme() {
        let region = Region.custom(host: "chat.local", pushAPIHost: "push.local", port: 8080, isSecure: false)

        storage().save(token(region: region))

        XCTAssertEqual(mirrored?.reportBaseURL.absoluteString, "http://push.local:8080")
    }

    func testTheMirrorFollowsTheRegionOfTheToken() {
        storage().save(token(region: .US1))

        XCTAssertEqual(mirrored?.reportBaseURL.absoluteString, "https://grpc.sinch-push.us1.prod.sinch.com")
    }
}

final class MirrorBackingAuthStorage: AuthStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var token: AuthModel?

    func read() -> AuthModel? { lock.withLock { token } }
    func save(_ token: AuthModel) { lock.withLock { self.token = token } }
    func deleteToken() { lock.withLock { token = nil } }
}
