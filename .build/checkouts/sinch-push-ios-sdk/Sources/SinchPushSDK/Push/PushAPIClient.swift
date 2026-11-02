import Foundation
import SinchPushSDKNotificationExtension

/// Abstraction over the push transport.
///
/// sinch-push answers native gRPC (`application/grpc+proto`) and puts `grpc-status` in the HTTP/2 trailers, which
/// `URLSession` does not expose. The gRPC-web framing and the message frame work unchanged; the client therefore runs
/// with ``GrpcWebClient/MissingStatusPolicy/acceptIfMessageReceived``: a status in the headers is an error, a received
/// message frame is a success.
protocol PushAPIClient: Sendable {
    /// The gRPC-web client of the push service, `nil` when the region has no usable host.
    var grpcWebClient: GrpcWebClient? { get }

    func closeChannel()
}

final class DefaultPushAPIClient: PushAPIClient, @unchecked Sendable {

    private let client: GrpcWebClient?

    /// `nil` when the region has no usable push host.
    init?(region: Region) {
        guard let url = Self.baseURL(region: region) else { return nil }
        self.client = GrpcWebClient(baseURL: url, missingStatusPolicy: .acceptIfMessageReceived)
    }

    deinit {
        closeChannel()
    }

    var grpcWebClient: GrpcWebClient? { client }

    func closeChannel() {
        // `URLSession` owns its connections; there is no channel to close.
    }

    // MARK: - Private

    static func baseURL(region: Region) -> URL? {
        ReportEndpoint.baseURL(pushHost: region.pushAPIHost, port: region.port, isSecure: region.isSecure)
    }
}
