// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/chat/adapter/v1alpha1/commands.proto
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

struct Sinch_Chat_Adapter_V1alpha1_SendPayload {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var id: String = String()

  var projectID: String = String()

  var appID: String = String()

  var uuid: String = String()

  var payload: Sinch_Chat_Adapter_V1alpha1_SendPayload.OneOf_Payload? = nil

  var contactMessage: Sinch_Conversationapi_Type_ContactMessage {
    get {
      if case .contactMessage(let v)? = payload {return v}
      return Sinch_Conversationapi_Type_ContactMessage()
    }
    set {payload = .contactMessage(newValue)}
  }

  var contactEvent: Sinch_Conversationapi_Type_ContactEvent {
    get {
      if case .contactEvent(let v)? = payload {return v}
      return Sinch_Conversationapi_Type_ContactEvent()
    }
    set {payload = .contactEvent(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Payload: Equatable {
    case contactMessage(Sinch_Conversationapi_Type_ContactMessage)
    case contactEvent(Sinch_Conversationapi_Type_ContactEvent)

  #if !swift(>=4.1)
    static func ==(lhs: Sinch_Chat_Adapter_V1alpha1_SendPayload.OneOf_Payload, rhs: Sinch_Chat_Adapter_V1alpha1_SendPayload.OneOf_Payload) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.contactMessage, .contactMessage): return {
        guard case .contactMessage(let l) = lhs, case .contactMessage(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.contactEvent, .contactEvent): return {
        guard case .contactEvent(let l) = lhs, case .contactEvent(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.chat.adapter.v1alpha1"

extension Sinch_Chat_Adapter_V1alpha1_SendPayload: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SendPayload"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .standard(proto: "project_id"),
    3: .standard(proto: "app_id"),
    4: .same(proto: "uuid"),
    101: .standard(proto: "contact_message"),
    102: .standard(proto: "contact_event"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.id) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.projectID) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.appID) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.uuid) }()
      case 101: try {
        var v: Sinch_Conversationapi_Type_ContactMessage?
        var hadOneofValue = false
        if let current = self.payload {
          hadOneofValue = true
          if case .contactMessage(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.payload = .contactMessage(v)
        }
      }()
      case 102: try {
        var v: Sinch_Conversationapi_Type_ContactEvent?
        var hadOneofValue = false
        if let current = self.payload {
          hadOneofValue = true
          if case .contactEvent(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.payload = .contactEvent(v)
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
    if !self.id.isEmpty {
      try visitor.visitSingularStringField(value: self.id, fieldNumber: 1)
    }
    if !self.projectID.isEmpty {
      try visitor.visitSingularStringField(value: self.projectID, fieldNumber: 2)
    }
    if !self.appID.isEmpty {
      try visitor.visitSingularStringField(value: self.appID, fieldNumber: 3)
    }
    if !self.uuid.isEmpty {
      try visitor.visitSingularStringField(value: self.uuid, fieldNumber: 4)
    }
    switch self.payload {
    case .contactMessage?: try {
      guard case .contactMessage(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 101)
    }()
    case .contactEvent?: try {
      guard case .contactEvent(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 102)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Adapter_V1alpha1_SendPayload, rhs: Sinch_Chat_Adapter_V1alpha1_SendPayload) -> Bool {
    if lhs.id != rhs.id {return false}
    if lhs.projectID != rhs.projectID {return false}
    if lhs.appID != rhs.appID {return false}
    if lhs.uuid != rhs.uuid {return false}
    if lhs.payload != rhs.payload {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
