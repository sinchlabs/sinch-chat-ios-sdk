// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/policy/v1/contact_retention_policy_service.proto
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

struct Sinch_Conversationapi_Policy_V1_UpdateContactRetentionPolicyRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The Project ID to update the policy for.
  var projectID: String = String()

  /// Required. The updated policy.
  var policy: Sinch_Conversationapi_Policy_V1_ContactRetentionDuration {
    get {return _policy ?? Sinch_Conversationapi_Policy_V1_ContactRetentionDuration()}
    set {_policy = newValue}
  }
  /// Returns true if `policy` has been explicitly set.
  var hasPolicy: Bool {return self._policy != nil}
  /// Clears the value of `policy`. Subsequent reads from it will return its default value.
  mutating func clearPolicy() {self._policy = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _policy: Sinch_Conversationapi_Policy_V1_ContactRetentionDuration? = nil
}

struct Sinch_Conversationapi_Policy_V1_DeleteContactRetentionPolicyRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The Project ID to delete the policy for.
  var projectID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Policy_V1_GetContactRetentionPolicyRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The Project ID to get the policy for.
  var projectID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Policy_V1_ContactRetentionDuration {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The number of days to retain contacts for.
  ///
  /// The contacts may be deleted up to 24hours after the end of the retention
  /// period. The value must be within the range [1, 3650]. 
  var days: UInt32 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.policy.v1"

extension Sinch_Conversationapi_Policy_V1_UpdateContactRetentionPolicyRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".UpdateContactRetentionPolicyRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .same(proto: "policy"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._policy) }()
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
    try { if let v = self._policy {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Policy_V1_UpdateContactRetentionPolicyRequest, rhs: Sinch_Conversationapi_Policy_V1_UpdateContactRetentionPolicyRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs._policy != rhs._policy {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Policy_V1_DeleteContactRetentionPolicyRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DeleteContactRetentionPolicyRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Policy_V1_DeleteContactRetentionPolicyRequest, rhs: Sinch_Conversationapi_Policy_V1_DeleteContactRetentionPolicyRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Policy_V1_GetContactRetentionPolicyRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GetContactRetentionPolicyRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Policy_V1_GetContactRetentionPolicyRequest, rhs: Sinch_Conversationapi_Policy_V1_GetContactRetentionPolicyRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Policy_V1_ContactRetentionDuration: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ContactRetentionDuration"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "days"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.days) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.days != 0 {
      try visitor.visitSingularUInt32Field(value: self.days, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Policy_V1_ContactRetentionDuration, rhs: Sinch_Conversationapi_Policy_V1_ContactRetentionDuration) -> Bool {
    if lhs.days != rhs.days {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
