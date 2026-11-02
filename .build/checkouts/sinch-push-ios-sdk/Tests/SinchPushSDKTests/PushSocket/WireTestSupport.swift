import Foundation

@testable import SinchPushSDK

enum Wire {

    // Builds malformed envelopes independently of FrameCodec.

    // MARK: - Hex

    static func bytes(hex: String) -> [UInt8] {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(clean.count % 2 == 0, "odd-length hex: \(clean)")
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else {
                fatalError("not hex: \(clean[index..<next])")
            }
            out.append(byte)
            index = next
        }
        return out
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hex(_ values: [UInt8]) -> String {
        hex(Data(values))
    }

    static func data(_ values: [UInt8]) -> Data {
        Data(values)
    }

    // MARK: - Varints

    static func varintSize(_ value: UInt64) -> Int {
        var size = 1
        var rest = value >> 7
        while rest != 0 {
            size += 1
            rest >>= 7
        }
        return size
    }

    static func varintBytes(_ value: UInt64) -> [UInt8] {
        var out: [UInt8] = []
        var rest = value
        while rest >= 0x80 {
            out.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        out.append(UInt8(rest))
        return out
    }

    /// ``varintBytes(_:)`` padded to `width` bytes with the same value. Leading `0x80`
    /// bytes would change the value, so the terminal byte becomes a continuation and
    /// zero groups follow:
    ///
    ///     65536 canonical   80 80 04
    ///     extended to 10    80 80 84 80 80 80 80 80 80 00
    static func extendedVarint(_ value: UInt64, width: Int) -> [UInt8] {
        var groups = varintBytes(value)
        precondition(
            width >= groups.count, "cannot extend a \(groups.count)-byte varint to \(width) bytes")
        if width == groups.count { return groups }
        groups[groups.count - 1] |= 0x80  // terminal becomes a continuation
        return groups + [UInt8](repeating: 0x80, count: width - groups.count - 1) + [0x00]
    }

    // MARK: - Envelopes

    static func bytesOf(_ parts: [UInt8]...) -> [UInt8] {
        parts.reduce(into: []) { $0 += $1 }
    }

    /// `[tag][varint(payload.length)][payload]`, written out by hand.
    static func envelope(tag: UInt8, payload: [UInt8]) -> [UInt8] {
        bytesOf([tag], varintBytes(UInt64(payload.count)), payload)
    }

    /// `[tag][prefix as given][body]`, for prefixes ``varintBytes(_:)`` cannot produce.
    static func envelopeWithPrefix(tag: UInt8, prefix: [UInt8], body: [UInt8] = []) -> [UInt8] {
        bytesOf([tag], prefix, body)
    }

    /// `[tag][varint(declared)][filler]`, where the body is deliberately too short.
    static func frameDeclaring(tag: UInt8, declared: UInt64, bodyBytes: Int) -> [UInt8] {
        bytesOf([tag], varintBytes(declared), [UInt8](repeating: 0x41, count: bodyBytes))
    }

    // MARK: - Payloads

    /// A `Pong` whose serialised form is exactly `size` bytes.
    static func pongMessageOfSize(_ size: Int) -> Sinch_Push_Delivery_V1beta1_Ws_Pong {
        for length in stride(from: size, through: 0, by: -1) {
            let candidate = String(repeating: "C", count: length)
            let message = pongMessage(correlationID: candidate)
            if (try? message.serializedData().count) == size { return message }
        }
        fatalError("no Pong payload serialises to exactly \(size) bytes")
    }

    static func pongPayloadOfSize(_ size: Int) -> Data {
        guard let payload = try? pongMessageOfSize(size).serializedData() else {
            fatalError("the Pong payload of \(size) bytes does not serialise")
        }
        return payload
    }

    static func pongClientFrameOfSize(_ size: Int) -> Sinch_Push_Delivery_V1beta1_Ws_ClientFrame {
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .pong(pongMessageOfSize(size))
        return frame
    }

    static func pongServerFrameOfSize(_ size: Int) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
        frame.payload = .pong(pongMessageOfSize(size))
        return frame
    }

    static func pongMessage(correlationID: String) -> Sinch_Push_Delivery_V1beta1_Ws_Pong {
        var pong = Sinch_Push_Delivery_V1beta1_Ws_Pong()
        pong.correlationID = correlationID
        return pong
    }
}

extension Data {
    var bytes: [UInt8] { [UInt8](self) }
}
