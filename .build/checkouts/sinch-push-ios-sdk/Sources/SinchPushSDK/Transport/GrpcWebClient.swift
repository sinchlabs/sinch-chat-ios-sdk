import Foundation
import SwiftProtobuf

/// A gRPC-web client over `URLSession`.
///
/// gRPC-web is gRPC framed for HTTP: a unary call is one `POST` whose body is the length
/// prefixed protobuf message, and whose answer is the message frame followed by a trailer
/// frame carrying `grpc-status`. It needs no HTTP/2 and no gRPC runtime, which is what a
/// standalone push SDK wants.
///
/// ```swift
/// let client = GrpcWebClient(baseURL: URL(string: "https://grpc-web.sinch-chat.prod.sinch.com")!)
/// let token: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
///     path: "sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken",
///     request: request,
///     metadata: [:]
/// )
/// ```
///
/// ## What a server answers
///
/// The chat backend speaks gRPC-web: it answers `application/grpc-web+proto` and puts the
/// status in the trailer frame of the body, or in the HTTP headers when it refuses the call
/// before sending a message.
///
/// The push backend speaks **native gRPC**: it answers `application/grpc+proto` and puts the
/// status in the HTTP/2 trailers, which `URLSession` does not expose. A call to the push
/// backend therefore arrives without a status. See ``MissingStatusPolicy``.
public struct GrpcWebClient: Sendable {

    /// The content type of a gRPC-web protobuf call.
    public static let contentType = "application/grpc-web+proto"

    /// What to do when the answer carries no `grpc-status` at all.
    public enum MissingStatusPolicy: Sendable {
        /// Fail the call. The right choice for a server that speaks gRPC-web: it always
        /// sends a status, so a missing one means the answer is not what it should be.
        case fail
        /// Accept the call when the server sent a response message.
        ///
        /// A gRPC server sends a message frame only when the call succeeded, so the presence
        /// of one tells success from failure. The status itself stays invisible.
        case acceptIfMessageReceived
        /// Record the answer as it is, with no status, and report it.
        ///
        /// The way to observe what a native gRPC server answers: the call did not fail at
        /// the transport level, but the server refused it and the status stayed in the
        /// HTTP/2 trailers.
        case record
    }

    /// The base URL of the gRPC-web service, without a trailing slash.
    public let baseURL: URL

    private let session: URLSession
    private let missingStatusPolicy: MissingStatusPolicy

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL of the service, for example `https://grpc-web.sinch-chat.prod.sinch.com`.
    ///   - session: The session to use. The default is a session with a per request timeout of 30 seconds.
    ///   - missingStatusPolicy: What to do when the answer carries no status.
    public init(baseURL: URL,
                session: URLSession? = nil,
                missingStatusPolicy: MissingStatusPolicy = .fail) {
        self.baseURL = baseURL
        self.missingStatusPolicy = missingStatusPolicy
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Calls a unary gRPC-web method.
    ///
    /// - Parameters:
    ///   - path: The method path, for example `sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken`.
    ///   - request: The request message.
    ///   - metadata: The request headers. The `authorization` header carries the raw JWT, with no `Bearer` prefix.
    ///   - timeout: The timeout of the call. `nil` leaves it to the session.
    /// - Returns: The response message.
    /// - Throws: ``GrpcWebError``.
    public func unary<Req: SwiftProtobuf.Message, Res: SwiftProtobuf.Message>(
        path: String,
        request: Req,
        metadata: [String: String] = [:],
        timeout: Duration? = nil
    ) async throws -> Res {
        let call = try await call(path: path, request: request, metadata: metadata, timeout: timeout)
        guard let payload = call.messages.first else {
            // A call that answers with no message is a call with an empty response.
            return try decode(Res.self, from: Data())
        }
        return try decode(Res.self, from: payload)
    }

    /// Calls a unary gRPC-web method and keeps everything the server said.
    ///
    /// Use this when the status matters more than the message: the push backend is a native
    /// gRPC server, and over HTTP/1.1 it answers without the trailer frame, so the status is
    /// only visible when the server repeats it in a header.
    ///
    /// - Parameters:
    ///   - path: The method path, for example `sinch.push.sdk.v1beta1.SdkService/Subscribe`.
    ///   - request: The request message.
    ///   - metadata: The request headers.
    ///   - timeout: The timeout of the call.
    /// - Returns: The frames of the answer and the status the server reported.
    /// - Throws: ``GrpcWebError`` when the call did not reach the server, when the server
    ///   answered with a non-zero `grpc-status`, or when the answer carried no status and
    ///   the policy is ``MissingStatusPolicy/fail``.
    public func call<Req: SwiftProtobuf.Message>(
        path: String,
        request: Req,
        metadata: [String: String] = [:],
        timeout: Duration? = nil
    ) async throws -> GrpcWebCall {
        var urlRequest = URLRequest(url: url(for: path))
        urlRequest.httpMethod = "POST"
        for (key, value) in metadata {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        // The gRPC-web headers are set last, so a caller can not break the framing by accident.
        urlRequest.setValue(Self.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(Self.contentType, forHTTPHeaderField: "Accept")
        urlRequest.setValue("1", forHTTPHeaderField: "X-Grpc-Web")
        urlRequest.httpBody = GrpcWebFraming.frame(try request.serializedData())
        if let timeout {
            urlRequest.timeoutInterval = timeout.seconds
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GrpcWebError.transport(description: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GrpcWebError.transport(description: "the answer is not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GrpcWebError.httpStatus(code: http.statusCode, body: data)
        }

        let body = try GrpcWebFraming.parse(data)
        // The status travels in the trailer frame, or in a header when the server answers
        // over a protocol that cannot carry trailers.
        let headerStatus = http.value(forHTTPHeaderField: "grpc-status").flatMap { Int($0) }
        let headerMessage = http.value(forHTTPHeaderField: "grpc-message")
        let status = body.trailerStatus ?? headerStatus
        let message = body.trailerMessage ?? headerMessage

        guard let status else {
            // No status anywhere: the answer is a native gRPC answer over HTTP/2, whose
            // trailers `URLSession` does not expose.
            switch missingStatusPolicy {
            case .fail:
                throw GrpcWebError.missingStatus(sawResponseMessage: !body.messages.isEmpty)
            case .acceptIfMessageReceived:
                guard !body.messages.isEmpty else {
                    throw GrpcWebError.missingStatus(sawResponseMessage: false)
                }
            case .record:
                break
            }
            return GrpcWebCall(
                httpStatus: http.statusCode,
                messages: body.messages,
                trailers: body.trailers,
                status: nil,
                message: nil,
                responseHeaders: http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                    result["\(entry.key)"] = "\(entry.value)"
                }
            )
        }
        guard status == GrpcWebStatus.ok else {
            throw GrpcWebError.grpcStatus(code: status, message: message)
        }

        return GrpcWebCall(
            httpStatus: http.statusCode,
            messages: body.messages,
            trailers: body.trailers,
            status: status,
            message: message,
            responseHeaders: http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                result["\(entry.key)"] = "\(entry.value)"
            }
        )
    }

    /// The URL of a method.
    ///
    /// The path is appended verbatim: a gRPC method path carries a slash
    /// (`sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken`), which a path component
    /// helper may percent-encode.
    public func url(for path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        let prefix = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.percentEncodedPath = prefix + "/" + suffix
        return components.url ?? baseURL
    }

    private func decode<Res: SwiftProtobuf.Message>(_ type: Res.Type, from payload: Data) throws -> Res {
        do {
            return try Res(serializedBytes: payload)
        } catch {
            throw GrpcWebError.decodingFailed(reason: error.localizedDescription)
        }
    }
}

/// Everything a gRPC-web answer carried.
public struct GrpcWebCall: Sendable {
    /// The HTTP status of the answer.
    public let httpStatus: Int
    /// The message frames of the answer, in order.
    public let messages: [Data]
    /// The trailer frame of the answer.
    public let trailers: [String: String]
    /// The `grpc-status` the server reported, when it was visible.
    ///
    /// It is `nil` for a native gRPC answer over HTTP/2: the status is in the HTTP/2
    /// trailers, which `URLSession` does not expose.
    public let status: Int?
    /// The `grpc-message` the server reported, when it was visible.
    public let message: String?
    /// The HTTP headers of the answer.
    public let responseHeaders: [String: String]

    /// The first message frame of the answer.
    public var firstMessage: Data? { messages.first }

    /// Whether the server sent a message frame at all.
    ///
    /// A gRPC server sends a message frame only when the call succeeded.
    public var sawResponseMessage: Bool { !messages.isEmpty }
}

extension Duration {
    /// The duration in seconds, with the fractional part.
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
