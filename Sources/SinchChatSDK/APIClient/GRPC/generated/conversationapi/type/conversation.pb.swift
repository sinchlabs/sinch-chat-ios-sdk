// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/conversation.proto
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

/// Conversation
///
/// A collection of messages exchanged between a contact and an app.
/// Conversations are normally created on the fly by Conversation API once
/// a message is sent and there is no active conversation already.
/// There can be only one active conversation at any given time between
/// a particular contact and an app.
struct Sinch_Conversationapi_Type_Conversation {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The ID of the conversation.
  var id: String = String()

  /// The ID of the participating app.
  var appID: String = String()

  /// The ID of the participating contact.
  var contactID: String = String()

  /// Output only. The timestamp of the latest message in the conversation. The timestamp will be
  /// Thursday January 01, 1970 00:00:00 UTC if the conversation contains no messages. 
  var lastReceived: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _lastReceived ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_lastReceived = newValue}
  }
  /// Returns true if `lastReceived` has been explicitly set.
  var hasLastReceived: Bool {return self._lastReceived != nil}
  /// Clears the value of `lastReceived`. Subsequent reads from it will return its default value.
  mutating func clearLastReceived() {self._lastReceived = nil}

  /// Output only. The channel last used for communication in the conversation. The value will be
  /// CHANNEL_UNSPECIFIED if the conversation does not contain messages. 
  var activeChannel: Sinch_Conversationapi_Type_ConversationChannel = .channelUnspecified

  /// Flag for whether this conversation is active.
  var active: Bool = false

  /// An arbitrary data set by the Conversation API clients.
  /// Up to 1024 characters long. 
  var metadata: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _lastReceived: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_Conversation: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_Conversation: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Conversation"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .standard(proto: "app_id"),
    3: .standard(proto: "contact_id"),
    4: .standard(proto: "last_received"),
    5: .standard(proto: "active_channel"),
    6: .same(proto: "active"),
    7: .same(proto: "metadata"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.id) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.appID) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.contactID) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._lastReceived) }()
      case 5: try { try decoder.decodeSingularEnumField(value: &self.activeChannel) }()
      case 6: try { try decoder.decodeSingularBoolField(value: &self.active) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self.metadata) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.id.isEmpty {
      try visitor.visitSingularStringField(value: self.id, fieldNumber: 1)
    }
    if !self.appID.isEmpty {
      try visitor.visitSingularStringField(value: self.appID, fieldNumber: 2)
    }
    if !self.contactID.isEmpty {
      try visitor.visitSingularStringField(value: self.contactID, fieldNumber: 3)
    }
    try { if let v = self._lastReceived {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    if self.activeChannel != .channelUnspecified {
      try visitor.visitSingularEnumField(value: self.activeChannel, fieldNumber: 5)
    }
    if self.active != false {
      try visitor.visitSingularBoolField(value: self.active, fieldNumber: 6)
    }
    if !self.metadata.isEmpty {
      try visitor.visitSingularStringField(value: self.metadata, fieldNumber: 7)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_Conversation, rhs: Sinch_Conversationapi_Type_Conversation) -> Bool {
    if lhs.id != rhs.id {return false}
    if lhs.appID != rhs.appID {return false}
    if lhs.contactID != rhs.contactID {return false}
    if lhs._lastReceived != rhs._lastReceived {return false}
    if lhs.activeChannel != rhs.activeChannel {return false}
    if lhs.active != rhs.active {return false}
    if lhs.metadata != rhs.metadata {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
