// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/capability/v1/capability_service.proto
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

struct Sinch_Conversationapi_Capability_V1_QueryCapabilityRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The project ID.
  var projectID: String = String()

  /// Required. The ID of the app to use for capability lookup.
  var appID: String = String()

  /// Required. The recipient to do the lookup for.
  var recipient: Sinch_Conversationapi_Type_Recipient {
    get {return _recipient ?? Sinch_Conversationapi_Type_Recipient()}
    set {_recipient = newValue}
  }
  /// Returns true if `recipient` has been explicitly set.
  var hasRecipient: Bool {return self._recipient != nil}
  /// Clears the value of `recipient`. Subsequent reads from it will return its default value.
  mutating func clearRecipient() {self._recipient = nil}

  ///
  /// ID for the asynchronous request, will be generated if not set.
  /// Currently this field is not used for idempotency but it will be added in v1
  var requestID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _recipient: Sinch_Conversationapi_Type_Recipient? = nil
}

/// Represents an explicit Capability registration
///
/// An CapabilityResponse contains the identity of the recipient for which
/// will be perform a capability lookup.
struct Sinch_Conversationapi_Capability_V1_QueryCapabilityResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The ID of the app to use for capability lookup.
  var appID: String = String()

  /// Required. The recipient for which a capability lookup was triggered for.
  var recipient: Sinch_Conversationapi_Type_Recipient {
    get {return _recipient ?? Sinch_Conversationapi_Type_Recipient()}
    set {_recipient = newValue}
  }
  /// Returns true if `recipient` has been explicitly set.
  var hasRecipient: Bool {return self._recipient != nil}
  /// Clears the value of `recipient`. Subsequent reads from it will return its default value.
  mutating func clearRecipient() {self._recipient = nil}

  /// ID for the asynchronous request, will be generated id if not set in request
  var requestID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _recipient: Sinch_Conversationapi_Type_Recipient? = nil
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.capability.v1"

extension Sinch_Conversationapi_Capability_V1_QueryCapabilityRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".QueryCapabilityRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "app_id"),
    3: .same(proto: "recipient"),
    4: .standard(proto: "request_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.appID) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._recipient) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.requestID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    if !self.appID.isEmpty {
      try visitor.visitSingularStringField(value: self.appID, fieldNumber: 2)
    }
    try { if let v = self._recipient {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    if !self.requestID.isEmpty {
      try visitor.visitSingularStringField(value: self.requestID, fieldNumber: 4)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Capability_V1_QueryCapabilityRequest, rhs: Sinch_Conversationapi_Capability_V1_QueryCapabilityRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.appID != rhs.appID {return false}
    if lhs._recipient != rhs._recipient {return false}
    if lhs.requestID != rhs.requestID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Capability_V1_QueryCapabilityResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".QueryCapabilityResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "app_id"),
    2: .same(proto: "recipient"),
    3: .standard(proto: "request_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.appID) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._recipient) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.requestID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.appID.isEmpty {
      try visitor.visitSingularStringField(value: self.appID, fieldNumber: 1)
    }
    try { if let v = self._recipient {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    if !self.requestID.isEmpty {
      try visitor.visitSingularStringField(value: self.requestID, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Capability_V1_QueryCapabilityResponse, rhs: Sinch_Conversationapi_Capability_V1_QueryCapabilityResponse) -> Bool {
    if lhs.appID != rhs.appID {return false}
    if lhs._recipient != rhs._recipient {return false}
    if lhs.requestID != rhs.requestID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
