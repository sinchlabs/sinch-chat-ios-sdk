import Foundation
import GRPC
import Logging

public enum Region: Codable, Equatable {
    case EU1
    case US1
    case custom(host: String, pushAPIHost: String)
}

internal var triggerFatalError = Swift.fatalError

protocol APIClient {
    var isChannelStarted: Bool { get }
    
    func getChannel() -> GRPCChannel
    func closeChannel()
    func startChannel()
}

final class DefaultAPIClient: APIClient {

    private static var logger: Logging.Logger = {
        var logger = Logging.Logger(label: "SINCH GRPC CLIENT", factory: StreamLogHandler.standardOutput(label:))
        logger.logLevel = .warning
        return logger
    }()
    private static let group = PlatformSupport.makeEventLoopGroup(loopCount: 1, networkPreference: .best, logger: logger)

    private let host: String
    private let port = 443
    var isChannelStarted = false
    
    private var channel: GRPCChannel
    
    init?(region: Region) {
        switch region {
        case .EU1:
            host = "sdk.sinch-chat.unauth.prod.sinch.com"
        case .US1:
           
            host = "sdk.sinch-chat.us1.prod.sinch.com"
        case .custom(let host, _):
            self.host = host
        }
        
        let keepalive = ClientConnectionKeepalive(
            interval: .seconds(10),
            timeout: .seconds(5)
        )
        do {
            channel = try GRPCChannelPool
                .with(target: .hostAndPort(host, port),
                      transportSecurity: .tls(.makeClientConfigurationBackedByNIOSSL()),
                      eventLoopGroup: DefaultAPIClient.group) {
                    $0.keepalive = keepalive
                }
            isChannelStarted = true
        } catch let error {
            Logger.error("error during creating GRPCChannelPool", error.localizedDescription)
            return nil
        }
    }
    func startChannel() {
        let keepalive = ClientConnectionKeepalive(
            interval: .seconds(10),
            timeout: .seconds(5)
        )
        
        do {
            channel = try GRPCChannelPool
                .with(target: .hostAndPort(host, port),
                      transportSecurity: .tls(.makeClientConfigurationBackedByNIOSSL()),
                      eventLoopGroup: DefaultAPIClient.group) {
                    $0.keepalive = keepalive
                }
            isChannelStarted = true

        } catch let error {
            Logger.error("error during creating GRPCChannelPool", error.localizedDescription)
        }
    }
    
    func getChannel() -> GRPCChannel {
        channel
    }
    
    func closeChannel() {
        _ = channel.close()
        isChannelStarted = false
        debugPrint("*********CLOSE CHANEL************")
    }
}
