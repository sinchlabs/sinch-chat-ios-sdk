import Foundation

/// What a gRPC-web call can go wrong with.
public enum GrpcWebError: Error, Sendable, Equatable, CustomStringConvertible {

    /// The HTTP status was not 2xx. The body is kept: a proxy error page explains itself.
    case httpStatus(code: Int, body: Data)

    /// The server answered with a non-zero `grpc-status`.
    case grpcStatus(code: Int, message: String?)

    /// The answer carried no `grpc-status` at all, neither in the trailer frame nor in the
    /// HTTP headers.
    ///
    /// This is what a native gRPC server answers over HTTP/1.1: the status travels in the
    /// HTTP/2 trailers, which HTTP/1.1 cannot carry, so the status is lost. `sawResponseMessage`
    /// tells whether the server sent a response message: gRPC only sends one when the call
    /// succeeded, so `true` means the call did succeed and only the status is missing.
    case missingStatus(sawResponseMessage: Bool)

    /// The body is not a sequence of gRPC-web frames.
    case malformedFrame(reason: String)

    /// The response message could not be decoded into the expected protobuf type.
    case decodingFailed(reason: String)

    /// The request never completed: DNS, TLS, timeout, connection reset.
    case transport(description: String)

    public var description: String {
        switch self {
        case .httpStatus(let code, _):
            return "HTTP status \(code)"
        case .grpcStatus(let code, let message):
            return "grpc-status \(code): \(message ?? "")"
        case .missingStatus(let sawResponseMessage):
            return "no grpc-status in the answer (response message seen: \(sawResponseMessage))"
        case .malformedFrame(let reason):
            return "malformed gRPC-web body: \(reason)"
        case .decodingFailed(let reason):
            return "cannot decode the response message: \(reason)"
        case .transport(let description):
            return "transport failure: \(description)"
        }
    }

    /// The gRPC status code of a failed call, when the failure carries one.
    public var grpcStatusCode: Int? {
        if case .grpcStatus(let code, _) = self { return code }
        return nil
    }
}

/// The gRPC status codes, as they appear in `grpc-status`.
public enum GrpcWebStatus {
    public static let ok = 0
    public static let cancelled = 1
    public static let unknown = 2
    public static let invalidArgument = 3
    public static let deadlineExceeded = 4
    public static let notFound = 5
    public static let alreadyExists = 6
    public static let permissionDenied = 7
    public static let resourceExhausted = 8
    public static let failedPrecondition = 9
    public static let aborted = 10
    public static let outOfRange = 11
    public static let unimplemented = 12
    public static let internalError = 13
    public static let unavailable = 14
    public static let dataLoss = 15
    public static let unauthenticated = 16

    /// The name of a gRPC status code, for logs and test failure messages.
    public static func name(_ code: Int) -> String {
        switch code {
        case ok: return "OK"
        case cancelled: return "CANCELLED"
        case unknown: return "UNKNOWN"
        case invalidArgument: return "INVALID_ARGUMENT"
        case deadlineExceeded: return "DEADLINE_EXCEEDED"
        case notFound: return "NOT_FOUND"
        case alreadyExists: return "ALREADY_EXISTS"
        case permissionDenied: return "PERMISSION_DENIED"
        case resourceExhausted: return "RESOURCE_EXHAUSTED"
        case failedPrecondition: return "FAILED_PRECONDITION"
        case aborted: return "ABORTED"
        case outOfRange: return "OUT_OF_RANGE"
        case unimplemented: return "UNIMPLEMENTED"
        case internalError: return "INTERNAL"
        case unavailable: return "UNAVAILABLE"
        case dataLoss: return "DATA_LOSS"
        case unauthenticated: return "UNAUTHENTICATED"
        default: return "STATUS_\(code)"
        }
    }
}
