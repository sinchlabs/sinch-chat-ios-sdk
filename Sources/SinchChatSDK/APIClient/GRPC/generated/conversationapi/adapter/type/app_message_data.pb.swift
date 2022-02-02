// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/adapter/type/app_message_data.proto
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

struct Sinch_Conversationapi_Adapter_Type_AppMessageData {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. Channel credential
  var channelCredential: Sinch_Conversationapi_Type_ConversationChannelCredential {
    get {return _storage._channelCredential ?? Sinch_Conversationapi_Type_ConversationChannelCredential()}
    set {_uniqueStorage()._channelCredential = newValue}
  }
  /// Returns true if `channelCredential` has been explicitly set.
  var hasChannelCredential: Bool {return _storage._channelCredential != nil}
  /// Clears the value of `channelCredential`. Subsequent reads from it will return its default value.
  mutating func clearChannelCredential() {_uniqueStorage()._channelCredential = nil}

  /// Channel identity of the recipient
  var to: String {
    get {return _storage._to}
    set {_uniqueStorage()._to = newValue}
  }

  var message: OneOf_Message? {
    get {return _storage._message}
    set {_uniqueStorage()._message = newValue}
  }

  var appMessage: Sinch_Conversationapi_Type_AppMessage {
    get {
      if case .appMessage(let v)? = _storage._message {return v}
      return Sinch_Conversationapi_Type_AppMessage()
    }
    set {_uniqueStorage()._message = .appMessage(newValue)}
  }

  var appEvent: Sinch_Conversationapi_Type_AppEvent {
    get {
      if case .appEvent(let v)? = _storage._message {return v}
      return Sinch_Conversationapi_Type_AppEvent()
    }
    set {_uniqueStorage()._message = .appEvent(newValue)}
  }

  var conversationNotification: Sinch_Conversationapi_Type_ConversationNotification {
    get {
      if case .conversationNotification(let v)? = _storage._message {return v}
      return Sinch_Conversationapi_Type_ConversationNotification()
    }
    set {_uniqueStorage()._message = .conversationNotification(newValue)}
  }

  /// Optional. Channel-specific properties.
  /// The key in the map must point to a valid channel property key as
  /// defined by the enum ChannelPropertyKeys. 
  var channelProperties: Dictionary<String,String> {
    get {return _storage._channelProperties}
    set {_uniqueStorage()._channelProperties = newValue}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Message: Equatable {
    case appMessage(Sinch_Conversationapi_Type_AppMessage)
    case appEvent(Sinch_Conversationapi_Type_AppEvent)
    case conversationNotification(Sinch_Conversationapi_Type_ConversationNotification)

  #if !swift(>=4.1)
    static func ==(lhs: Sinch_Conversationapi_Adapter_Type_AppMessageData.OneOf_Message, rhs: Sinch_Conversationapi_Adapter_Type_AppMessageData.OneOf_Message) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.appMessage, .appMessage): return {
        guard case .appMessage(let l) = lhs, case .appMessage(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.appEvent, .appEvent): return {
        guard case .appEvent(let l) = lhs, case .appEvent(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.conversationNotification, .conversationNotification): return {
        guard case .conversationNotification(let l) = lhs, case .conversationNotification(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.adapter.type"

extension Sinch_Conversationapi_Adapter_Type_AppMessageData: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AppMessageData"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "channel_credential"),
    2: .same(proto: "to"),
    3: .standard(proto: "app_message"),
    4: .standard(proto: "app_event"),
    6: .standard(proto: "conversation_notification"),
    5: .standard(proto: "channel_properties"),
  ]

  fileprivate class _StorageClass {
    var _channelCredential: Sinch_Conversationapi_Type_ConversationChannelCredential? = nil
    var _to: String = String()
    var _message: Sinch_Conversationapi_Adapter_Type_AppMessageData.OneOf_Message?
    var _channelProperties: Dictionary<String,String> = [:]

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _channelCredential = source._channelCredential
      _to = source._to
      _message = source._message
      _channelProperties = source._channelProperties
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularMessageField(value: &_storage._channelCredential) }()
        case 2: try { try decoder.decodeSingularStringField(value: &_storage._to) }()
        case 3: try {
          var v: Sinch_Conversationapi_Type_AppMessage?
          var hadOneofValue = false
          if let current = _storage._message {
            hadOneofValue = true
            if case .appMessage(let m) = current {v = m}
          }
          try decoder.decodeSingularMessageField(value: &v)
          if let v = v {
            if hadOneofValue {try decoder.handleConflictingOneOf()}
            _storage._message = .appMessage(v)
          }
        }()
        case 4: try {
          var v: Sinch_Conversationapi_Type_AppEvent?
          var hadOneofValue = false
          if let current = _storage._message {
            hadOneofValue = true
            if case .appEvent(let m) = current {v = m}
          }
          try decoder.decodeSingularMessageField(value: &v)
          if let v = v {
            if hadOneofValue {try decoder.handleConflictingOneOf()}
            _storage._message = .appEvent(v)
          }
        }()
        case 5: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString,SwiftProtobuf.ProtobufString>.self, value: &_storage._channelProperties) }()
        case 6: try {
          var v: Sinch_Conversationapi_Type_ConversationNotification?
          var hadOneofValue = false
          if let current = _storage._message {
            hadOneofValue = true
            if case .conversationNotification(let m) = current {v = m}
          }
          try decoder.decodeSingularMessageField(value: &v)
          if let v = v {
            if hadOneofValue {try decoder.handleConflictingOneOf()}
            _storage._message = .conversationNotification(v)
          }
        }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every if/case branch local when no optimizations
      // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
      // https://github.com/apple/swift-protobuf/issues/1182
      try { if let v = _storage._channelCredential {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
      } }()
      if !_storage._to.isEmpty {
        try visitor.visitSingularStringField(value: _storage._to, fieldNumber: 2)
      }
      switch _storage._message {
      case .appMessage?: try {
        guard case .appMessage(let v)? = _storage._message else { preconditionFailure() }
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      }()
      case .appEvent?: try {
        guard case .appEvent(let v)? = _storage._message else { preconditionFailure() }
        try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
      }()
      default: break
      }
      if !_storage._channelProperties.isEmpty {
        try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString,SwiftProtobuf.ProtobufString>.self, value: _storage._channelProperties, fieldNumber: 5)
      }
      try { if case .conversationNotification(let v)? = _storage._message {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Adapter_Type_AppMessageData, rhs: Sinch_Conversationapi_Adapter_Type_AppMessageData) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._channelCredential != rhs_storage._channelCredential {return false}
        if _storage._to != rhs_storage._to {return false}
        if _storage._message != rhs_storage._message {return false}
        if _storage._channelProperties != rhs_storage._channelProperties {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
