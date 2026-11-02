import Foundation

/// The gRPC-web wire format: a length-prefixed frame per message, and a trailer
/// frame with the call status.
///
/// A frame is one flag byte, a big-endian `UInt32` length and that many bytes.
/// Flag `0x00` carries a protobuf message, flag `0x80` carries the trailers as
/// `key: value` lines.
public enum GrpcWebFraming {

    /// The flag byte of a frame that carries a protobuf message.
    public static let messageFlag: UInt8 = 0x00
    /// The flag byte of a frame that carries the trailers.
    public static let trailerFlag: UInt8 = 0x80
    /// The length of the frame header: one flag byte and a four byte length.
    public static let headerLength = 5

    /// Wraps a serialized protobuf message in a gRPC-web frame.
    public static func frame(_ payload: Data) -> Data {
        var framed = Data([messageFlag])
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }

    /// Wraps the trailers of a call in a gRPC-web trailer frame.
    ///
    /// The trailers travel as `key: value` lines, each ending with CRLF.
    public static func trailerFrame(_ trailers: [String: String]) -> Data {
        var text = ""
        for key in trailers.keys.sorted() {
            text += "\(key): \(trailers[key] ?? "")\r\n"
        }
        let payload = Data(text.utf8)
        var framed = Data([trailerFlag])
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }

    /// Reads the frames of a gRPC-web body.
    ///
    /// - Throws: ``GrpcWebError/malformedFrame(reason:)`` when the body is cut short.
    public static func parse(_ body: Data) throws -> GrpcWebBody {
        var messages: [Data] = []
        var trailers: [String: String] = [:]
        let bytes = [UInt8](body)
        var offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= headerLength else {
                throw GrpcWebError.malformedFrame(reason: "a frame header is cut short")
            }
            let flag = bytes[offset]
            let length = bytes[(offset + 1)...(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += headerLength
            guard length >= 0, offset + length <= bytes.count else {
                throw GrpcWebError.malformedFrame(reason: "a frame of \(length) bytes is cut short")
            }
            let payload = Data(bytes[offset..<(offset + length)])
            offset += length
            if flag & trailerFlag != 0 {
                for (key, value) in parseTrailers(payload) { trailers[key] = value }
            } else {
                messages.append(payload)
            }
        }
        return GrpcWebBody(messages: messages, trailers: trailers)
    }

    /// Reads the `key: value` lines of a trailer frame.
    public static func parseTrailers(_ payload: Data) -> [String: String] {
        var result: [String: String] = [:]
        let text = String(decoding: payload, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}

/// The frames of a gRPC-web body.
public struct GrpcWebBody: Sendable, Equatable {
    /// The protobuf messages of the call, in order.
    public let messages: [Data]
    /// The trailers of the call: `grpc-status`, `grpc-message`, ...
    public let trailers: [String: String]

    public init(messages: [Data], trailers: [String: String]) {
        self.messages = messages
        self.trailers = trailers
    }

    /// The first message of the call, when there is one.
    public var firstMessage: Data? { messages.first }

    /// The `grpc-status` of the trailer frame, when the server sent one.
    public var trailerStatus: Int? {
        trailers["grpc-status"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The `grpc-message` of the trailer frame, when the server sent one.
    public var trailerMessage: String? { trailers["grpc-message"] }
}
