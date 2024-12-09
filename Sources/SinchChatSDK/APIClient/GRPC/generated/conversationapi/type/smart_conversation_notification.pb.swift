// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/smart_conversation_notification.proto
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

struct Sinch_Conversationapi_Type_SmartConversationNotification {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. The identifier of the contact who received the message. Will not be present for messages sent in Dispatch Mode.
  var contactID: String = String()

  /// Required. The channel identity of the recipient.
  var channelIdentity: String = String()

  /// Required. The channel from which the message was received.
  var channel: Sinch_Conversationapi_Type_ConversationChannel = .channelUnspecified

  /// Required. The ID of the analyzed message.
  var messageID: String = String()

  /// Optional. The ID of the conversation. Will not be present for messages sent in Dispatch Mode.
  var conversationID: String = String()

  /// Required. ML analysis result
  var analysisResults: SwiftProtobuf.Google_Protobuf_Struct {
    get {return _analysisResults ?? SwiftProtobuf.Google_Protobuf_Struct()}
    set {_analysisResults = newValue}
  }
  /// Returns true if `analysisResults` has been explicitly set.
  var hasAnalysisResults: Bool {return self._analysisResults != nil}
  /// Clears the value of `analysisResults`. Subsequent reads from it will return its default value.
  mutating func clearAnalysisResults() {self._analysisResults = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _analysisResults: SwiftProtobuf.Google_Protobuf_Struct? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_SmartConversationNotification: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_SmartConversationNotification: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SmartConversationNotification"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "contact_id"),
    2: .standard(proto: "channel_identity"),
    3: .same(proto: "channel"),
    4: .standard(proto: "message_id"),
    5: .standard(proto: "conversation_id"),
    6: .standard(proto: "analysis_results"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.contactID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.channelIdentity) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self.channel) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.messageID) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.conversationID) }()
      case 6: try { try decoder.decodeSingularMessageField(value: &self._analysisResults) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.contactID.isEmpty {
      try visitor.visitSingularStringField(value: self.contactID, fieldNumber: 1)
    }
    if !self.channelIdentity.isEmpty {
      try visitor.visitSingularStringField(value: self.channelIdentity, fieldNumber: 2)
    }
    if self.channel != .channelUnspecified {
      try visitor.visitSingularEnumField(value: self.channel, fieldNumber: 3)
    }
    if !self.messageID.isEmpty {
      try visitor.visitSingularStringField(value: self.messageID, fieldNumber: 4)
    }
    if !self.conversationID.isEmpty {
      try visitor.visitSingularStringField(value: self.conversationID, fieldNumber: 5)
    }
    try { if let v = self._analysisResults {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_SmartConversationNotification, rhs: Sinch_Conversationapi_Type_SmartConversationNotification) -> Bool {
    if lhs.contactID != rhs.contactID {return false}
    if lhs.channelIdentity != rhs.channelIdentity {return false}
    if lhs.channel != rhs.channel {return false}
    if lhs.messageID != rhs.messageID {return false}
    if lhs.conversationID != rhs.conversationID {return false}
    if lhs._analysisResults != rhs._analysisResults {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
