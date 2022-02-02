// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/chat/client/v1alpha2/client.proto
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

struct Sinch_Chat_Client_V1alpha2_CreateRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var client: Sinch_Chat_Client_V1alpha2_Client {
    get {return _client ?? Sinch_Chat_Client_V1alpha2_Client()}
    set {_client = newValue}
  }
  /// Returns true if `client` has been explicitly set.
  var hasClient: Bool {return self._client != nil}
  /// Clears the value of `client`. Subsequent reads from it will return its default value.
  mutating func clearClient() {self._client = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _client: Sinch_Chat_Client_V1alpha2_Client? = nil
}

struct Sinch_Chat_Client_V1alpha2_GetRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var clientID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Chat_Client_V1alpha2_ListRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var pageSize: Int32 = 0

  var pageToken: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Chat_Client_V1alpha2_ListResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var clients: [Sinch_Chat_Client_V1alpha2_Client] = []

  var nextPageToken: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Chat_Client_V1alpha2_UpdateRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var client: Sinch_Chat_Client_V1alpha2_Client {
    get {return _client ?? Sinch_Chat_Client_V1alpha2_Client()}
    set {_client = newValue}
  }
  /// Returns true if `client` has been explicitly set.
  var hasClient: Bool {return self._client != nil}
  /// Clears the value of `client`. Subsequent reads from it will return its default value.
  mutating func clearClient() {self._client = nil}

  var updateMask: SwiftProtobuf.Google_Protobuf_FieldMask {
    get {return _updateMask ?? SwiftProtobuf.Google_Protobuf_FieldMask()}
    set {_updateMask = newValue}
  }
  /// Returns true if `updateMask` has been explicitly set.
  var hasUpdateMask: Bool {return self._updateMask != nil}
  /// Clears the value of `updateMask`. Subsequent reads from it will return its default value.
  mutating func clearUpdateMask() {self._updateMask = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _client: Sinch_Chat_Client_V1alpha2_Client? = nil
  fileprivate var _updateMask: SwiftProtobuf.Google_Protobuf_FieldMask? = nil
}

struct Sinch_Chat_Client_V1alpha2_DeleteRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var clientID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Chat_Client_V1alpha2_SignUuidRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var clientID: String = String()

  var uuid: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Chat_Client_V1alpha2_SignUuidResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var uuidHash: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.chat.client.v1alpha2"

extension Sinch_Chat_Client_V1alpha2_CreateRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".CreateRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "client"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._client) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._client {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_CreateRequest, rhs: Sinch_Chat_Client_V1alpha2_CreateRequest) -> Bool {
    if lhs._client != rhs._client {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_GetRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GetRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "client_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.clientID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    if !self.clientID.isEmpty {
      try visitor.visitSingularStringField(value: self.clientID, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_GetRequest, rhs: Sinch_Chat_Client_V1alpha2_GetRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.clientID != rhs.clientID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_ListRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ListRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "page_size"),
    3: .standard(proto: "page_token"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self.pageSize) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.pageToken) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    if self.pageSize != 0 {
      try visitor.visitSingularInt32Field(value: self.pageSize, fieldNumber: 2)
    }
    if !self.pageToken.isEmpty {
      try visitor.visitSingularStringField(value: self.pageToken, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_ListRequest, rhs: Sinch_Chat_Client_V1alpha2_ListRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.pageSize != rhs.pageSize {return false}
    if lhs.pageToken != rhs.pageToken {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_ListResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ListResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "clients"),
    2: .standard(proto: "next_page_token"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.clients) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.nextPageToken) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.clients.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.clients, fieldNumber: 1)
    }
    if !self.nextPageToken.isEmpty {
      try visitor.visitSingularStringField(value: self.nextPageToken, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_ListResponse, rhs: Sinch_Chat_Client_V1alpha2_ListResponse) -> Bool {
    if lhs.clients != rhs.clients {return false}
    if lhs.nextPageToken != rhs.nextPageToken {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_UpdateRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".UpdateRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .same(proto: "client"),
    3: .standard(proto: "update_mask"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._client) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._updateMask) }()
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
    try { if let v = self._client {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._updateMask {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_UpdateRequest, rhs: Sinch_Chat_Client_V1alpha2_UpdateRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs._client != rhs._client {return false}
    if lhs._updateMask != rhs._updateMask {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_DeleteRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DeleteRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "client_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.clientID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    if !self.clientID.isEmpty {
      try visitor.visitSingularStringField(value: self.clientID, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_DeleteRequest, rhs: Sinch_Chat_Client_V1alpha2_DeleteRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.clientID != rhs.clientID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_SignUuidRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SignUuidRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "client_id"),
    3: .same(proto: "uuid"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.clientID) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.uuid) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 1)
    }
    if !self.clientID.isEmpty {
      try visitor.visitSingularStringField(value: self.clientID, fieldNumber: 2)
    }
    if !self.uuid.isEmpty {
      try visitor.visitSingularStringField(value: self.uuid, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_SignUuidRequest, rhs: Sinch_Chat_Client_V1alpha2_SignUuidRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.clientID != rhs.clientID {return false}
    if lhs.uuid != rhs.uuid {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Client_V1alpha2_SignUuidResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SignUuidResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    3: .standard(proto: "uuid_hash"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 3: try { try decoder.decodeSingularStringField(value: &self.uuidHash) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.uuidHash.isEmpty {
      try visitor.visitSingularStringField(value: self.uuidHash, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Client_V1alpha2_SignUuidResponse, rhs: Sinch_Chat_Client_V1alpha2_SignUuidResponse) -> Bool {
    if lhs.uuidHash != rhs.uuidHash {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
