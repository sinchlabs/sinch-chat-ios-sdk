import Foundation

/// One APNs delivery, as `ReportEvents` carries it.
package struct ReportedDelivery: Codable, Hashable, Sendable {
    package let messageID: String
    package let subscriberID: String

    package init(messageID: String, subscriberID: String) {
        self.messageID = messageID
        self.subscriberID = subscriberID
    }
}

/// `sinch.push.sdk.v1beta1.SdkService/ReportEvents` over gRPC-web, as a plain HTTPS POST.
///
/// The request is encoded by hand: three fields of two messages are not worth a protobuf dependency in an extension.
/// `ReportEventsRequest.events = 1` repeats `ReportedEvent { message_id = 1, subscriber_id = 2, event_type = 4 }`,
/// and `event_type` is always DELIVERED (300).
package enum GRPCWebReportEvents {
    package static let path = "sinch.push.sdk.v1beta1.SdkService/ReportEvents"
    package static let contentType = "application/grpc-web+proto"

    /// The `PushEventType.DELIVERED` value.
    package static let deliveredEventType: UInt64 = 300

    /// Builds the POST for `deliveries`. The body is sent from a file, so it is not part of the request.
    package static func request(baseURL: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentType, forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "X-Grpc-Web")
        request.setValue(accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    /// The gRPC-web body: one uncompressed message frame (`0x00`, big-endian length, protobuf).
    package static func body(for deliveries: [ReportedDelivery]) -> Data {
        let message = protobuf(for: deliveries)
        var framed = Data([0x00])
        withUnsafeBytes(of: UInt32(message.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(message)
        return framed
    }

    /// The `ReportEventsRequest` message.
    package static func protobuf(for deliveries: [ReportedDelivery]) -> Data {
        var message = Data()
        for delivery in deliveries {
            var event = Data()
            appendString(delivery.messageID, field: 1, to: &event)
            appendString(delivery.subscriberID, field: 2, to: &event)
            appendVarint(tag(field: 4, wireType: 0), to: &event)
            appendVarint(deliveredEventType, to: &event)
            appendVarint(tag(field: 1, wireType: 2), to: &message)
            appendVarint(UInt64(event.count), to: &message)
            message.append(event)
        }
        return message
    }

    // MARK: - Response

    /// How a `ReportEvents` call ended.
    package enum Outcome: Equatable, Sendable {
        case success
        /// The HTTP status was not 2xx.
        case httpFailure(status: Int)
        /// The server answered with a non-zero `grpc-status`.
        case grpcFailure(status: Int, message: String?)
        /// A frame was cut short, or the answer carries no `grpc-status` at all.
        case malformed
    }

    /// Reads the outcome of the call. The status is in the `0x80` trailer frame, or in the `grpc-status` header.
    /// A 2xx answer that carries neither is `malformed`, not a success: an intermediary that answers 200 on its own
    /// (a captive portal, a proxy error page) must not mark the delivery as reported.
    package static func outcome(httpStatus: Int, headerGrpcStatus: String?, body: Data) -> Outcome {
        guard (200..<300).contains(httpStatus) else { return .httpFailure(status: httpStatus) }
        var trailer: [String: String] = [:]
        let bytes = [UInt8](body)
        var offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 5 else { return .malformed }
            let flag = bytes[offset]
            let length = bytes[(offset + 1)...(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 5
            guard length >= 0, offset + length <= bytes.count else { return .malformed }
            if flag & 0x80 != 0 {
                let text = String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
                for (key, value) in parseTrailer(text) { trailer[key] = value }
            }
            offset += length
        }
        let rawStatus = trailer["grpc-status"] ?? headerGrpcStatus
        guard let rawStatus else { return .malformed }
        guard let status = Int(rawStatus.trimmingCharacters(in: .whitespaces)) else { return .malformed }
        guard status != 0 else { return .success }
        return .grpcFailure(status: status, message: trailer["grpc-message"])
    }

    static func parseTrailer(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    // MARK: - Protobuf

    private static func tag(field: UInt64, wireType: UInt64) -> UInt64 {
        (field << 3) | wireType
    }

    private static func appendString(_ value: String, field: UInt64, to data: inout Data) {
        // proto3 leaves a default value out.
        guard !value.isEmpty else { return }
        let bytes = Data(value.utf8)
        appendVarint(tag(field: field, wireType: 2), to: &data)
        appendVarint(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var rest = value
        while rest >= 0x80 {
            data.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        data.append(UInt8(rest))
    }
}

/// The host that serves `ReportEvents` for a push API host.
package enum ReportEndpoint {
    package static let eu1Host = "grpc.sinch-push.prod.sinch.com"
    package static let us1Host = "grpc.sinch-push.us1.prod.sinch.com"

    /// The base URL of the push API. gRPC-web shares the host of gRPC, on 443 unless `port` says otherwise.
    ///
    /// - Parameters:
    ///   - pushHost: A host name. A `host:port` (the port wins over `port`), or a leading `http://` / `https://`
    ///     (the scheme wins over `isSecure`), is accepted too; a path is dropped. An IPv6 address is bare (`::1`, no
    ///     port) or in brackets (`[::1]`, `[::1]:8443`).
    ///   - port: The port of a custom region. `nil` leaves it to the scheme.
    ///   - isSecure: `false` makes the URL `http`, for a plaintext custom region.
    /// - Returns: `nil` when no valid URL can be made from the host.
    package static func baseURL(pushHost: String, port: Int? = nil, isSecure: Bool = true) -> URL? {
        var host = pushHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var port = port
        var secure = isSecure
        if let separator = host.range(of: "://") {
            secure = host[..<separator.lowerBound].lowercased() != "http"
            host = String(host[separator.upperBound...])
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        // A port follows a host name or a bracketed IPv6 address; a bare IPv6 address, which has several colons, has none.
        let colons = host.filter { $0 == ":" }.count
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return nil }
            let rest = host[host.index(after: close)...]
            if !rest.isEmpty {
                guard rest.hasPrefix(":"), let embedded = Int(rest.dropFirst()) else { return nil }
                port = embedded
            }
            host = String(host[host.index(after: host.startIndex)..<close])
        } else if colons == 1, let colon = host.firstIndex(of: ":") {
            guard let embedded = Int(host[host.index(after: colon)...]) else { return nil }
            port = embedded
            host = String(host[..<colon])
        }
        guard !host.isEmpty, port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        var components = URLComponents()
        components.scheme = secure ? "https" : "http"
        // `URLComponents` takes an IPv6 address in brackets.
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = port
        return components.url
    }
}
