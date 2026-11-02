/// Encodes and decodes `[tag][varint payload length][protobuf payload]`.
///
/// The tag is the protobuf field number of the frame's `oneof payload` member.
/// Rebuilding the frame message as `key || length || payload` lets the generated
/// decoder resolve the payload, so no payload switch is written here.

import Foundation
import SwiftProtobuf

/// Which side of the connection a frame travels on.
///
/// A tag only has meaning with a direction: field 4 is `ClientFrame.pong` inbound
/// and `ServerFrame.ack` outbound.
enum FrameDirection: String, Sendable, Equatable {
    case client
    case server
}

/// Why an envelope could not be read or written.
enum FrameCodecError: Error, Equatable, Sendable {
    /// Fewer than a tag byte plus a length byte.
    case tooShort(direction: FrameDirection)
    /// The length prefix is unterminated, or overflows 64 bits.
    case lengthVarint(direction: FrameDirection, detail: String)
    /// The declared (or to-be-written) payload is over `maxFramePayloadBytes`.
    case payloadTooLarge(direction: FrameDirection, declaredLength: UInt64)
    /// The whole frame is over `maxFrameTotalBytes`.
    case frameTooLarge(direction: FrameDirection, length: Int)
    /// Fewer payload bytes are present than the prefix declared.
    case truncatedPayload(direction: FrameDirection, declaredLength: Int, available: Int)
    /// The tag does not name a payload of the expected frame type. The envelope
    /// itself is fine; the peer is ahead of this build.
    case unknownTag(direction: FrameDirection, tag: UInt8)
    /// The bytes inside the envelope are not a well-formed payload message.
    case malformedPayload(direction: FrameDirection, tag: UInt8, detail: String)
    /// Nothing was set in the frame's `oneof payload`, so there is no envelope.
    case noPayloadSet(direction: FrameDirection)
    /// The frame's serialisation is not one length-delimited field.
    case noEnvelope(direction: FrameDirection, detail: String)
}

extension FrameCodecError: CustomStringConvertible {
    var description: String {
        switch self {
        case .tooShort(let direction):
            return "ws frame (\(direction)): too short"
        case .lengthVarint(let direction, let detail):
            return "ws frame (\(direction)): \(detail)"
        case .payloadTooLarge(let direction, let declaredLength):
            return "ws frame (\(direction)): declared payload \(declaredLength) bytes exceeds \(FrameCodec.maxFramePayloadBytes)"
        case .frameTooLarge(let direction, let length):
            return "ws frame (\(direction)): \(length) bytes exceeds the \(FrameCodec.maxFrameTotalBytes)-byte frame limit"
        case .truncatedPayload(let direction, let declaredLength, let available):
            return "ws frame (\(direction)): truncated payload (need \(declaredLength) bytes, have \(available))"
        case .unknownTag(let direction, let tag):
            return "ws frame (\(direction)): unknown frame tag \(tag)"
        case .malformedPayload(let direction, let tag, let detail):
            return "ws frame (\(direction)): payload for tag \(tag) does not parse (\(detail))"
        case .noPayloadSet(let direction):
            return "ws frame (\(direction)): frame has no payload set"
        case .noEnvelope(let direction, let detail):
            return "ws frame (\(direction)): \(detail)"
        }
    }
}

extension FrameCodecError: LocalizedError {
    var errorDescription: String? { description }
}

enum FrameCodec {
    /// Largest protobuf payload a frame may carry. The relay enforces the same
    /// bound inbound, before allocating, and outbound, before writing.
    static let maxFramePayloadBytes = 65_536

    /// Widest prefix this SDK writes: `65536` encodes as three bytes.
    static let canonicalLengthVarintMaxBytes = 3

    /// Widest prefix a 64-bit length can occupy. Non-canonical encodings are accepted.
    static let lengthVarintMaxBytes64 = 10

    /// Largest whole frame accepted: 1 tag byte, 10 prefix bytes, 65536 payload bytes.
    /// Nothing is allocated from a length prefix alone; the payload cap is the limit.
    static let maxFrameTotalBytes = maxFramePayloadBytes + 1 + lengthVarintMaxBytes64

    /// Largest frame written. Writes use a canonical prefix, so this is narrower
    /// than what is accepted.
    static let maxFrameEmittedBytes =
        maxFramePayloadBytes + 1 + canonicalLengthVarintMaxBytes

    /// Decode an inbound server frame.
    ///
    /// - Throws: ``FrameCodecError/unknownTag(direction:tag:)`` when the tag names
    ///   no `ServerFrame` payload, and a malformed-envelope error otherwise.
    static func decodeServerFrame(
        _ data: Data
    ) throws -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
        let decoded: (frame: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame, tag: UInt8) =
            try decodeFrame(data, direction: .server)
        guard decoded.frame.payload != nil else {
            throw FrameCodecError.unknownTag(direction: .server, tag: decoded.tag)
        }
        return decoded.frame
    }

    /// Decode an inbound client frame. Used by tests and golden vectors only.
    static func decodeClientFrame(
        _ data: Data
    ) throws -> Sinch_Push_Delivery_V1beta1_Ws_ClientFrame {
        let decoded: (frame: Sinch_Push_Delivery_V1beta1_Ws_ClientFrame, tag: UInt8) =
            try decodeFrame(data, direction: .client)
        guard decoded.frame.payload != nil else {
            throw FrameCodecError.unknownTag(direction: .client, tag: decoded.tag)
        }
        return decoded.frame
    }

    /// Encode a `ClientFrame` as `[tag][varint length][protobuf payload]`.
    static func encodeClientFrame(
        _ frame: Sinch_Push_Delivery_V1beta1_Ws_ClientFrame
    ) throws -> Data {
        try encodeFrame(frame, direction: .client) { $0.payload == nil }
    }

    /// Encode a `ServerFrame` the same way.
    static func encodeServerFrame(
        _ frame: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame
    ) throws -> Data {
        try encodeFrame(frame, direction: .server) { $0.payload == nil }
    }

    /// A frame split into its envelope tag and the span of its protobuf encoding.
    private struct Envelope {
        let direction: FrameDirection
        let tag: UInt8
        /// Offsets from the start of the buffer, not `Data` indices.
        let bodyStart: Int
        let bodyEnd: Int
    }

    /// Read the envelope, applying both bounds before anything is sliced.
    private static func readEnvelope(_ direction: FrameDirection, _ data: Data) throws -> Envelope {
        guard data.count >= 2 else {
            throw FrameCodecError.tooShort(direction: direction)
        }
        guard data.count <= maxFrameTotalBytes else {
            throw FrameCodecError.frameTooLarge(direction: direction, length: data.count)
        }
        let (tag, declaredLength, prefixWidth) = try data.withUnsafeBytes { raw in
            let tag = raw[0]
            let (length, width) = try readVarint(direction: direction, bytes: raw, from: 1)
            return (tag, length, width)
        }
        // Check the 64-bit length before narrowing it to Int.
        guard declaredLength <= UInt64(maxFramePayloadBytes) else {
            throw FrameCodecError.payloadTooLarge(
                direction: direction, declaredLength: declaredLength)
        }
        let length = Int(declaredLength)
        let bodyStart = 1 + prefixWidth
        // Cannot overflow: both operands are at most 65547.
        let bodyEnd = bodyStart + length
        guard bodyEnd <= data.count else {
            throw FrameCodecError.truncatedPayload(
                direction: direction,
                declaredLength: length,
                available: max(0, data.count - bodyStart)
            )
        }
        return Envelope(direction: direction, tag: tag, bodyStart: bodyStart, bodyEnd: bodyEnd)
    }

    /// Rebuild the frame message's protobuf encoding from a received envelope:
    /// the raw tag byte becomes the key it stands for, and the prefix and payload
    /// are copied verbatim, including a non-canonical prefix.
    private static func protobufBody(
        direction: FrameDirection,
        envelope: Envelope,
        of data: Data
    ) throws -> Data {
        // Field number 0 is reserved and never names a payload.
        guard envelope.tag != 0 else {
            throw FrameCodecError.unknownTag(direction: direction, tag: envelope.tag)
        }
        // `(fieldNumber << 3) | 2`: a `oneof` payload is always length-delimited.
        let key = UInt32(envelope.tag) << 3 | 0x02
        var body = Data()
        body.reserveCapacity(envelope.bodyEnd - 1 + keyWidth(for: key))
        appendCanonicalVarint(UInt64(key), to: &body)
        body.append(data[(data.startIndex + 1)..<(data.startIndex + envelope.bodyEnd)])
        return body
    }

    /// Split a frame message's serialisation into its envelope tag and payload.
    private static func splitEnvelope(
        direction: FrameDirection,
        _ wire: Data
    ) throws -> (tag: UInt8, payload: Data) {
        // Unreachable with a payload set; typed rather than trapping.
        guard wire.count >= 2 else {
            throw FrameCodecError.noEnvelope(
                direction: direction,
                detail: "a frame with a payload set serialises to at least two bytes, got \(wire.count)"
            )
        }
        return try wire.withUnsafeBytes { raw -> (UInt8, Data) in
            let (key, keyWidth) = try readVarint(direction: direction, bytes: raw, from: 0)
            guard key & 0x07 == 0x02 else {
                throw FrameCodecError.noEnvelope(
                    direction: direction,
                    detail: "frame serialised with wire type \(key & 0x07), expected length-delimited"
                )
            }
            let fieldNumber = key >> 3
            guard fieldNumber >= 1, fieldNumber <= UInt64(UInt8.max) else {
                throw FrameCodecError.noEnvelope(
                    direction: direction,
                    detail: "payload field number \(fieldNumber) does not fit the one-byte envelope tag"
                )
            }
            let (length, lengthWidth) = try readVarint(direction: direction, bytes: raw, from: keyWidth)
            let bodyStart = keyWidth + lengthWidth
            // Holds for the generated encoder's output; checked to avoid a trap.
            guard length <= UInt64(raw.count - bodyStart) else {
                throw FrameCodecError.noEnvelope(
                    direction: direction,
                    detail: "serialised payload length \(length) exceeds the \(raw.count - bodyStart) bytes present"
                )
            }
            return (UInt8(fieldNumber), Data(raw[bodyStart..<(bodyStart + Int(length))]))
        }
    }

    private static func encodeFrame<M: SwiftProtobuf.Message>(
        _ frame: M,
        direction: FrameDirection,
        isPayloadless: (M) -> Bool
    ) throws -> Data {
        guard !isPayloadless(frame) else {
            throw FrameCodecError.noPayloadSet(direction: direction)
        }
        let wire: Data = try frame.serializedData()
        let envelope = try splitEnvelope(direction: direction, wire)
        return try writeEnvelope(direction: direction, tag: envelope.tag, payload: envelope.payload)
    }

    /// An unknown tag decodes without a payload rather than throwing, so the
    /// caller can tell it apart from bytes that do not parse.
    private static func decodeFrame<M: SwiftProtobuf.Message>(
        _ data: Data,
        direction: FrameDirection
    ) throws -> (frame: M, tag: UInt8) {
        let envelope = try readEnvelope(direction, data)
        let body = try protobufBody(direction: direction, envelope: envelope, of: data)
        let frame: M
        do {
            frame = try M(serializedBytes: body)
        } catch {
            throw FrameCodecError.malformedPayload(
                direction: direction, tag: envelope.tag, detail: "\(error)")
        }
        return (frame, envelope.tag)
    }

    private static func writeEnvelope(
        direction: FrameDirection,
        tag: UInt8,
        payload: Data
    ) throws -> Data {
        guard payload.count <= maxFramePayloadBytes else {
            throw FrameCodecError.payloadTooLarge(
                direction: direction, declaredLength: UInt64(payload.count))
        }
        var frame = Data()
        frame.reserveCapacity(1 + canonicalLengthVarintMaxBytes + payload.count)
        frame.append(tag)
        appendCanonicalVarint(UInt64(payload.count), to: &frame)
        frame.append(payload)
        // Unreachable while the payload cap holds; checked so it is enforced.
        guard frame.count <= maxFrameTotalBytes else {
            throw FrameCodecError.frameTooLarge(direction: direction, length: frame.count)
        }
        return frame
    }

    /// Read an unsigned varint at `offset`. The 64-bit value is checked against
    /// the payload bound before narrowing. Rejects an unterminated prefix and a
    /// tenth byte with more than its one free bit.
    private static func readVarint(
        direction: FrameDirection,
        bytes: UnsafeRawBufferPointer,
        from offset: Int
    ) throws -> (value: UInt64, width: Int) {
        var value: UInt64 = 0
        for index in 0..<lengthVarintMaxBytes64 {
            guard offset + index < bytes.count else {
                throw FrameCodecError.lengthVarint(
                    direction: direction, detail: "unterminated length varint after \(index) bytes")
            }
            let byte = bytes[offset + index]
            if index == lengthVarintMaxBytes64 - 1 && byte > 0x01 {
                throw FrameCodecError.lengthVarint(
                    direction: direction, detail: "length varint overflows 64 bits")
            }
            // index <= 9, so the shift is at most 63.
            value |= UInt64(byte & 0x7F) << (7 * UInt64(index))
            if byte & 0x80 == 0 {
                return (value, index + 1)
            }
        }
        throw FrameCodecError.lengthVarint(
            direction: direction, detail: "length varint overflows 64 bits")
    }

    /// Bytes an unsigned varint of `value` occupies on the wire.
    static func varintWidth(_ value: UInt64) -> Int {
        var width = 1
        var rest = value >> 7
        while rest != 0 {
            width += 1
            rest >>= 7
        }
        return width
    }

    /// Bytes a protobuf key for `value` occupies.
    static func keyWidth(for key: UInt32) -> Int {
        varintWidth(UInt64(key))
    }

    /// Append `value` as a minimal varint.
    private static func appendCanonicalVarint(_ value: UInt64, to data: inout Data) {
        var rest = value
        while rest >= 0x80 {
            data.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        data.append(UInt8(rest))
    }
}
