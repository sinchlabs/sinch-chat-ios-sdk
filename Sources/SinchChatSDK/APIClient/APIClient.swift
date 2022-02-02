import Foundation
import GRPC
import Logging
public enum Region: Codable, Equatable {
    case EU1
    case US1
    case custom(host: String)
}

protocol APIClient {
    func getChannel() -> ClientConnection
    func closeChannel()
}

final class DefaultAPIClient: APIClient {

    private var logger = Logging.Logger(label: "SINCH GRPC CLIENT", factory: StreamLogHandler.standardOutput(label:))
    private lazy var group = PlatformSupport.makeEventLoopGroup(loopCount: 1, networkPreference: .best, logger: logger)

    private let host: String
    private let port = 443

    lazy var channel = ClientConnection
        .usingPlatformAppropriateTLS(for: group)
        .withBackgroundActivityLogger(logger)
        .connect(host: host, port: port)
    
    init(region: Region) {
        switch region {
        case .EU1:
            host = "sdk.sinch-chat.unauth.prod.sinch.com"
        case .US1:
            fatalError("there is no url for US region provided yet")
            // host = "sdk.sinch-chat.unauth.staging.sinch.com"
        case .custom(let host):
            self.host = host
        }
        logger.logLevel = .info
    }
    
    func getChannel() -> ClientConnection {
        channel
    }
    
    func closeChannel() {
        _ = channel.close()
    }
}
