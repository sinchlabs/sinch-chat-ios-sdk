// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/adapter/v1beta/capability_service.proto
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

struct Sinch_Conversationapi_Adapter_V1beta_GetCapabilityRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. Channel credential.
  var channelCredential: Sinch_Conversationapi_Type_ConversationChannelCredential {
    get {return _channelCredential ?? Sinch_Conversationapi_Type_ConversationChannelCredential()}
    set {_channelCredential = newValue}
  }
  /// Returns true if `channelCredential` has been explicitly set.
  var hasChannelCredential: Bool {return self._channelCredential != nil}
  /// Clears the value of `channelCredential`. Subsequent reads from it will return its default value.
  mutating func clearChannelCredential() {self._channelCredential = nil}

  /// Channel identity for which to perform the capability check.
  var channelIdentity: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _channelCredential: Sinch_Conversationapi_Type_ConversationChannelCredential? = nil
}

struct Sinch_Conversationapi_Adapter_V1beta_GetCapabilityResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required.
  var capabilityStatus: Sinch_Conversationapi_Type_CapabilityStatus = .capabilityUnknown

  /// Optional. A reason shall be present if the capability check failed.
  var reason: Sinch_Conversationapi_Type_Reason {
    get {return _reason ?? Sinch_Conversationapi_Type_Reason()}
    set {_reason = newValue}
  }
  /// Returns true if `reason` has been explicitly set.
  var hasReason: Bool {return self._reason != nil}
  /// Clears the value of `reason`. Subsequent reads from it will return its default value.
  mutating func clearReason() {self._reason = nil}

  /// Optional. A list of channel-specific capability identifiers.
  var channelCapabilities: [String] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _reason: Sinch_Conversationapi_Type_Reason? = nil
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.adapter.v1beta"

extension Sinch_Conversationapi_Adapter_V1beta_GetCapabilityRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GetCapabilityRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "channel_credential"),
    2: .standard(proto: "channel_identity"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._channelCredential) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.channelIdentity) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._channelCredential {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    if !self.channelIdentity.isEmpty {
      try visitor.visitSingularStringField(value: self.channelIdentity, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Adapter_V1beta_GetCapabilityRequest, rhs: Sinch_Conversationapi_Adapter_V1beta_GetCapabilityRequest) -> Bool {
    if lhs._channelCredential != rhs._channelCredential {return false}
    if lhs.channelIdentity != rhs.channelIdentity {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Adapter_V1beta_GetCapabilityResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GetCapabilityResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "capability_status"),
    2: .same(proto: "reason"),
    3: .standard(proto: "channel_capabilities"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.capabilityStatus) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._reason) }()
      case 3: try { try decoder.decodeRepeatedStringField(value: &self.channelCapabilities) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.capabilityStatus != .capabilityUnknown {
      try visitor.visitSingularEnumField(value: self.capabilityStatus, fieldNumber: 1)
    }
    try { if let v = self._reason {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    if !self.channelCapabilities.isEmpty {
      try visitor.visitRepeatedStringField(value: self.channelCapabilities, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Adapter_V1beta_GetCapabilityResponse, rhs: Sinch_Conversationapi_Adapter_V1beta_GetCapabilityResponse) -> Bool {
    if lhs.capabilityStatus != rhs.capabilityStatus {return false}
    if lhs._reason != rhs._reason {return false}
    if lhs.channelCapabilities != rhs.channelCapabilities {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
