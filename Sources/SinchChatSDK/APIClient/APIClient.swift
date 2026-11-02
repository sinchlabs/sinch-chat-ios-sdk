import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCNIOTransportHTTP2Posix

internal nonisolated(unsafe) var triggerFatalError = Swift.fatalError

/// Abstraction over the chat gRPC transport.
protocol APIClient: Sendable {
    var isChannelStarted: Bool { get }

    func withClient<Result: Sendable>(handle: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> Result) async throws -> Result
    
    func closeChannel()
    func startChannel()
}

final class Default2APIClient: APIClient, @unchecked Sendable {

    private let host: String
    private let port: Int
    private let isSecure: Bool

    var isChannelStarted: Bool = true
    
    init?(region: Region) {
        switch region {
        case .EU1:
            self.host = "grpc.sinch-chat.prod.sinch.com"
            self.port = 443
            self.isSecure = true
        case .US1:
            self.host = "grpc.sinch-chat.us1.prod.sinch.com"
            self.port = 443
            self.isSecure = true
        case .custom(let host, _, let port, let isSecure, _):
            self.host = host
            self.port = port ?? 443
            self.isSecure = isSecure ?? true
        @unknown default:
            return nil
        }

        guard (try? Self.makeTransport(host: self.host, port: self.port, isSecure: self.isSecure)) != nil else {
            return nil
        }
    }
    
    func startChannel() {}
    func closeChannel() {}
    
    func withClient<Result: Sendable>(handle: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> Result) async throws -> Result {
        let transport = try Self.makeTransport(host: host, port: port, isSecure: isSecure)
        return try await withGRPCClient(transport: transport, handleClient: { grpcClient in
            try await handle(grpcClient)
        })
    }

    // MARK: - Private

    private static func makeTransport(host: String, port: Int, isSecure: Bool) throws -> HTTP2ClientTransport.Posix {
        try HTTP2ClientTransport.Posix.http2NIOPosix(
            target: .dns(host: host, port: port),
            transportSecurity: isSecure ? .tls : .plaintext
        )
    }
}
