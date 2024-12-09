import Foundation
import GRPC
import Logging

protocol PushAPIClient {
    func getChannel() -> GRPCChannel
    func closeChannel()
}

final class DefaultPushAPIClient: PushAPIClient {
    
    private static var logger: Logging.Logger = {
        var logger = Logging.Logger(label: "SINCH PUSH GRPC CLIENT", factory: StreamLogHandler.standardOutput(label:))
        logger.logLevel = .warning
        return logger
    }()
    private static let group = PlatformSupport.makeEventLoopGroup(loopCount: 1, networkPreference: .best, logger: logger)

    private let host: String
    private let port = 443

    private var channel: GRPCChannel
    
    init?(region: Region) {
        switch region {
        case .EU1:
            host = "grpc.sinch-push.prod.sinch.com"
        case .US1:
            host = "grpc.sinch-push.us1.prod.sinch.com"
        case .custom(_, let host):
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
                      eventLoopGroup: DefaultPushAPIClient.group) {
                    $0.keepalive = keepalive
                }
        } catch let error {
            Logger.error("error during creating GRPCPushChannelPool", error.localizedDescription)
            return nil
        }
    }
    
    func getChannel() -> GRPCChannel {
        channel
    }
    
    func closeChannel() {
        _ = channel.close()
    }
    
}
