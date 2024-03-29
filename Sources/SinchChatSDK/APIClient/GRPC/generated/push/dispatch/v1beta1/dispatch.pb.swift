// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/push/dispatch/v1beta1/dispatch.proto
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

struct Sinch_Push_Dispatch_V1beta1_DispatchRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var clientID: String = String()

  var userID: String = String()

  var payload: Sinch_Push_Dispatch_V1beta1_Payload {
    get {return _payload ?? Sinch_Push_Dispatch_V1beta1_Payload()}
    set {_payload = newValue}
  }
  /// Returns true if `payload` has been explicitly set.
  var hasPayload: Bool {return self._payload != nil}
  /// Clears the value of `payload`. Subsequent reads from it will return its default value.
  mutating func clearPayload() {self._payload = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _payload: Sinch_Push_Dispatch_V1beta1_Payload? = nil
}

struct Sinch_Push_Dispatch_V1beta1_DispatchedEvent {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var projectID: String = String()

  var clientID: String = String()

  var userID: String = String()

  var payload: Sinch_Push_Dispatch_V1beta1_Payload {
    get {return _payload ?? Sinch_Push_Dispatch_V1beta1_Payload()}
    set {_payload = newValue}
  }
  /// Returns true if `payload` has been explicitly set.
  var hasPayload: Bool {return self._payload != nil}
  /// Clears the value of `payload`. Subsequent reads from it will return its default value.
  mutating func clearPayload() {self._payload = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _payload: Sinch_Push_Dispatch_V1beta1_Payload? = nil
}

struct Sinch_Push_Dispatch_V1beta1_Payload {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var trackingID: String = String()

  var owner: String = String()

  var type: Sinch_Push_Dispatch_V1beta1_Payload.OneOf_Type? = nil

  var message: Sinch_Conversationapi_Type_AppMessage {
    get {
      if case .message(let v)? = type {return v}
      return Sinch_Conversationapi_Type_AppMessage()
    }
    set {type = .message(newValue)}
  }

  var event: Sinch_Conversationapi_Type_AppEvent {
    get {
      if case .event(let v)? = type {return v}
      return Sinch_Conversationapi_Type_AppEvent()
    }
    set {type = .event(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Type: Equatable {
    case message(Sinch_Conversationapi_Type_AppMessage)
    case event(Sinch_Conversationapi_Type_AppEvent)

  #if !swift(>=4.1)
    static func ==(lhs: Sinch_Push_Dispatch_V1beta1_Payload.OneOf_Type, rhs: Sinch_Push_Dispatch_V1beta1_Payload.OneOf_Type) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.message, .message): return {
        guard case .message(let l) = lhs, case .message(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.event, .event): return {
        guard case .event(let l) = lhs, case .event(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Push_Dispatch_V1beta1_DispatchRequest: @unchecked Sendable {}
extension Sinch_Push_Dispatch_V1beta1_DispatchedEvent: @unchecked Sendable {}
extension Sinch_Push_Dispatch_V1beta1_Payload: @unchecked Sendable {}
extension Sinch_Push_Dispatch_V1beta1_Payload.OneOf_Type: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.push.dispatch.v1beta1"

extension Sinch_Push_Dispatch_V1beta1_DispatchRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DispatchRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "client_id"),
    3: .standard(proto: "user_id"),
    4: .same(proto: "payload"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.clientID) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.userID) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._payload) }()
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
    if !self.clientID.isEmpty {
      try visitor.visitSingularStringField(value: self.clientID, fieldNumber: 2)
    }
    if !self.userID.isEmpty {
      try visitor.visitSingularStringField(value: self.userID, fieldNumber: 3)
    }
    try { if let v = self._payload {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Push_Dispatch_V1beta1_DispatchRequest, rhs: Sinch_Push_Dispatch_V1beta1_DispatchRequest) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.clientID != rhs.clientID {return false}
    if lhs.userID != rhs.userID {return false}
    if lhs._payload != rhs._payload {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Push_Dispatch_V1beta1_DispatchedEvent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DispatchedEvent"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "project_id"),
    2: .standard(proto: "client_id"),
    3: .standard(proto: "user_id"),
    4: .same(proto: "payload"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.clientID) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.userID) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._payload) }()
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
    if !self.clientID.isEmpty {
      try visitor.visitSingularStringField(value: self.clientID, fieldNumber: 2)
    }
    if !self.userID.isEmpty {
      try visitor.visitSingularStringField(value: self.userID, fieldNumber: 3)
    }
    try { if let v = self._payload {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Push_Dispatch_V1beta1_DispatchedEvent, rhs: Sinch_Push_Dispatch_V1beta1_DispatchedEvent) -> Bool {
    if lhs.projectID != rhs.projectID {return false}
    if lhs.clientID != rhs.clientID {return false}
    if lhs.userID != rhs.userID {return false}
    if lhs._payload != rhs._payload {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Push_Dispatch_V1beta1_Payload: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Payload"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "tracking_id"),
    2: .same(proto: "owner"),
    3: .same(proto: "message"),
    4: .same(proto: "event"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.trackingID) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.owner) }()
      case 3: try {
        var v: Sinch_Conversationapi_Type_AppMessage?
        var hadOneofValue = false
        if let current = self.type {
          hadOneofValue = true
          if case .message(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.type = .message(v)
        }
      }()
      case 4: try {
        var v: Sinch_Conversationapi_Type_AppEvent?
        var hadOneofValue = false
        if let current = self.type {
          hadOneofValue = true
          if case .event(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.type = .event(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.trackingID.isEmpty {
      try visitor.visitSingularStringField(value: self.trackingID, fieldNumber: 1)
    }
    if !self.owner.isEmpty {
      try visitor.visitSingularStringField(value: self.owner, fieldNumber: 2)
    }
    switch self.type {
    case .message?: try {
      guard case .message(let v)? = self.type else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .event?: try {
      guard case .event(let v)? = self.type else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Push_Dispatch_V1beta1_Payload, rhs: Sinch_Push_Dispatch_V1beta1_Payload) -> Bool {
    if lhs.trackingID != rhs.trackingID {return false}
    if lhs.owner != rhs.owner {return false}
    if lhs.type != rhs.type {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
