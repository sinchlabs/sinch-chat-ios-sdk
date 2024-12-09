// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/duplicated_contact_channel_identities_notification.proto
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

struct Sinch_Conversationapi_Type_DuplicatedContactChannelIdentitiesNotification {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// List which contains found duplicated identities 
  var duplicatedIdentities: [Sinch_Conversationapi_Type_DuplicatedIdentity] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Type_DuplicatedIdentity {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. Channel on which duplicated identity was found.
  var channel: Sinch_Conversationapi_Type_ConversationChannel = .channelUnspecified

  /// Required. List of contact_ids with duplicated channel identity.
  var contactIds: [String] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_DuplicatedContactChannelIdentitiesNotification: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_DuplicatedIdentity: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_DuplicatedContactChannelIdentitiesNotification: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DuplicatedContactChannelIdentitiesNotification"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "duplicated_identities"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.duplicatedIdentities) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.duplicatedIdentities.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.duplicatedIdentities, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_DuplicatedContactChannelIdentitiesNotification, rhs: Sinch_Conversationapi_Type_DuplicatedContactChannelIdentitiesNotification) -> Bool {
    if lhs.duplicatedIdentities != rhs.duplicatedIdentities {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_DuplicatedIdentity: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DuplicatedIdentity"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channel"),
    2: .standard(proto: "contact_ids"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.channel) }()
      case 2: try { try decoder.decodeRepeatedStringField(value: &self.contactIds) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.channel != .channelUnspecified {
      try visitor.visitSingularEnumField(value: self.channel, fieldNumber: 1)
    }
    if !self.contactIds.isEmpty {
      try visitor.visitRepeatedStringField(value: self.contactIds, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_DuplicatedIdentity, rhs: Sinch_Conversationapi_Type_DuplicatedIdentity) -> Bool {
    if lhs.channel != rhs.channel {return false}
    if lhs.contactIds != rhs.contactIds {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}