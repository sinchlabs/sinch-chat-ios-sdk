// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/unsupported_callback.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

/// Unsupported Channel Callback
///
/// A callback received on a channel which is not
/// natively supported by Conversation API. 
struct Sinch_Conversationapi_Type_UnsupportedCallback {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Output only. The originating channel of the unsupported callback.
  var channel: Sinch_Conversationapi_Type_ConversationChannel = .channelUnspecified

  /// Output only. The unsupported callback received by the Conversation API.
  var payload: String = String()

  /// Output only. The ID of the callback.
  var id: String = String()

  /// Output only. The ID of the conversation.
  var conversationID: String = String()

  /// Output only. The ID of the contact.
  var contactID: String = String()

  /// Output only. The contact channel identity of the callback.
  var channelIdentity: Sinch_Conversationapi_Type_ChannelIdentity {
    get {return _channelIdentity ?? Sinch_Conversationapi_Type_ChannelIdentity()}
    set {_channelIdentity = newValue}
  }
  /// Returns true if `channelIdentity` has been explicitly set.
  var hasChannelIdentity: Bool {return self._channelIdentity != nil}
  /// Clears the value of `channelIdentity`. Subsequent reads from it will return its default value.
  mutating func clearChannelIdentity() {self._channelIdentity = nil}

  /// Required. The processing mode.
  var processingMode: Sinch_Conversationapi_Type_ProcessingMode = .conversation

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _channelIdentity: Sinch_Conversationapi_Type_ChannelIdentity? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_UnsupportedCallback: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_UnsupportedCallback: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".UnsupportedCallback"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channel"),
    2: .same(proto: "payload"),
    3: .same(proto: "id"),
    4: .standard(proto: "conversation_id"),
    5: .standard(proto: "contact_id"),
    6: .standard(proto: "channel_identity"),
    7: .standard(proto: "processing_mode"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.channel) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.payload) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.id) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.conversationID) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.contactID) }()
      case 6: try { try decoder.decodeSingularMessageField(value: &self._channelIdentity) }()
      case 7: try { try decoder.decodeSingularEnumField(value: &self.processingMode) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.channel != .channelUnspecified {
      try visitor.visitSingularEnumField(value: self.channel, fieldNumber: 1)
    }
    if !self.payload.isEmpty {
      try visitor.visitSingularStringField(value: self.payload, fieldNumber: 2)
    }
    if !self.id.isEmpty {
      try visitor.visitSingularStringField(value: self.id, fieldNumber: 3)
    }
    if !self.conversationID.isEmpty {
      try visitor.visitSingularStringField(value: self.conversationID, fieldNumber: 4)
    }
    if !self.contactID.isEmpty {
      try visitor.visitSingularStringField(value: self.contactID, fieldNumber: 5)
    }
    try { if let v = self._channelIdentity {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    } }()
    if self.processingMode != .conversation {
      try visitor.visitSingularEnumField(value: self.processingMode, fieldNumber: 7)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_UnsupportedCallback, rhs: Sinch_Conversationapi_Type_UnsupportedCallback) -> Bool {
    if lhs.channel != rhs.channel {return false}
    if lhs.payload != rhs.payload {return false}
    if lhs.id != rhs.id {return false}
    if lhs.conversationID != rhs.conversationID {return false}
    if lhs.contactID != rhs.contactID {return false}
    if lhs._channelIdentity != rhs._channelIdentity {return false}
    if lhs.processingMode != rhs.processingMode {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
