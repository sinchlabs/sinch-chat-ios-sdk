// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/record_notification.proto
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

/// Record Notification
///
/// A record notification for an app. 
struct Sinch_Conversationapi_Type_RecordNotification {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The ID of the entity.
  var entityID: String = String()

  /// Required. The stored status.
  var recordStatus: Sinch_Conversationapi_Type_RecordStatus = .unspecified

  /// Required. The channel and contact channel identity of the entity.
  var channelIdentity: Sinch_Conversationapi_Type_ChannelIdentity {
    get {return _channelIdentity ?? Sinch_Conversationapi_Type_ChannelIdentity()}
    set {_channelIdentity = newValue}
  }
  /// Returns true if `channelIdentity` has been explicitly set.
  var hasChannelIdentity: Bool {return self._channelIdentity != nil}
  /// Clears the value of `channelIdentity`. Subsequent reads from it will return its default value.
  mutating func clearChannelIdentity() {self._channelIdentity = nil}

  /// Optional. The ID of the contact. Will not be present for apps in Dispatch Mode.
  var contactID: String = String()

  /// Optional. The ID of the conversation. Will not be present for apps in Dispatch Mode.
  var conversationID: String = String()

  /// Optional. A reason will be present if the status is FAILED.
  var reason: Sinch_Conversationapi_Type_Reason {
    get {return _reason ?? Sinch_Conversationapi_Type_Reason()}
    set {_reason = newValue}
  }
  /// Returns true if `reason` has been explicitly set.
  var hasReason: Bool {return self._reason != nil}
  /// Clears the value of `reason`. Subsequent reads from it will return its default value.
  mutating func clearReason() {self._reason = nil}

  /// Required. The processing mode.
  var processingMode: Sinch_Conversationapi_Type_ProcessingMode = .conversation

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _channelIdentity: Sinch_Conversationapi_Type_ChannelIdentity? = nil
  fileprivate var _reason: Sinch_Conversationapi_Type_Reason? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_RecordNotification: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_RecordNotification: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".RecordNotification"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "entity_id"),
    2: .standard(proto: "record_status"),
    3: .standard(proto: "channel_identity"),
    4: .standard(proto: "contact_id"),
    5: .standard(proto: "conversation_id"),
    6: .same(proto: "reason"),
    7: .standard(proto: "processing_mode"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.entityID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self.recordStatus) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._channelIdentity) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.contactID) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.conversationID) }()
      case 6: try { try decoder.decodeSingularMessageField(value: &self._reason) }()
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
    if !self.entityID.isEmpty {
      try visitor.visitSingularStringField(value: self.entityID, fieldNumber: 1)
    }
    if self.recordStatus != .unspecified {
      try visitor.visitSingularEnumField(value: self.recordStatus, fieldNumber: 2)
    }
    try { if let v = self._channelIdentity {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    if !self.contactID.isEmpty {
      try visitor.visitSingularStringField(value: self.contactID, fieldNumber: 4)
    }
    if !self.conversationID.isEmpty {
      try visitor.visitSingularStringField(value: self.conversationID, fieldNumber: 5)
    }
    try { if let v = self._reason {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    } }()
    if self.processingMode != .conversation {
      try visitor.visitSingularEnumField(value: self.processingMode, fieldNumber: 7)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_RecordNotification, rhs: Sinch_Conversationapi_Type_RecordNotification) -> Bool {
    if lhs.entityID != rhs.entityID {return false}
    if lhs.recordStatus != rhs.recordStatus {return false}
    if lhs._channelIdentity != rhs._channelIdentity {return false}
    if lhs.contactID != rhs.contactID {return false}
    if lhs.conversationID != rhs.conversationID {return false}
    if lhs._reason != rhs._reason {return false}
    if lhs.processingMode != rhs.processingMode {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
