// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/chat/sdk/v1alpha2/resources.proto
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

enum Sinch_Chat_Sdk_V1alpha2_PushPlatform: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case platformUnspecified // = 0
  case web // = 1
  case iosSandbox // = 2
  case ios // = 3
  case android // = 4
  case UNRECOGNIZED(Int)

  init() {
    self = .platformUnspecified
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .platformUnspecified
    case 1: self = .web
    case 2: self = .iosSandbox
    case 3: self = .ios
    case 4: self = .android
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .platformUnspecified: return 0
    case .web: return 1
    case .iosSandbox: return 2
    case .ios: return 3
    case .android: return 4
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Chat_Sdk_V1alpha2_PushPlatform: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Chat_Sdk_V1alpha2_PushPlatform] = [
    .platformUnspecified,
    .web,
    .iosSandbox,
    .ios,
    .android,
  ]
}

#endif  // swift(>=4.2)

enum Sinch_Chat_Sdk_V1alpha2_ChannelStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case `open` // = 0
  case closed // = 1
  case UNRECOGNIZED(Int)

  init() {
    self = .open
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .open
    case 1: self = .closed
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .open: return 0
    case .closed: return 1
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Chat_Sdk_V1alpha2_ChannelStatus: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Chat_Sdk_V1alpha2_ChannelStatus] = [
    .open,
    .closed,
  ]
}

#endif  // swift(>=4.2)

struct Sinch_Chat_Sdk_V1alpha2_Entry {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var deliveryTime: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _deliveryTime ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_deliveryTime = newValue}
  }
  /// Returns true if `deliveryTime` has been explicitly set.
  var hasDeliveryTime: Bool {return self._deliveryTime != nil}
  /// Clears the value of `deliveryTime`. Subsequent reads from it will return its default value.
  mutating func clearDeliveryTime() {self._deliveryTime = nil}

  var payload: Sinch_Chat_Sdk_V1alpha2_Entry.OneOf_Payload? = nil

  var appMessage: Sinch_Conversationapi_Type_AppMessage {
    get {
      if case .appMessage(let v)? = payload {return v}
      return Sinch_Conversationapi_Type_AppMessage()
    }
    set {payload = .appMessage(newValue)}
  }

  var appEvent: Sinch_Conversationapi_Type_AppEvent {
    get {
      if case .appEvent(let v)? = payload {return v}
      return Sinch_Conversationapi_Type_AppEvent()
    }
    set {payload = .appEvent(newValue)}
  }

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

  var entryID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Payload: Equatable {
    case appMessage(Sinch_Conversationapi_Type_AppMessage)
    case appEvent(Sinch_Conversationapi_Type_AppEvent)
    case contactMessage(Sinch_Conversationapi_Type_ContactMessage)
    case contactEvent(Sinch_Conversationapi_Type_ContactEvent)

  #if !swift(>=4.1)
    static func ==(lhs: Sinch_Chat_Sdk_V1alpha2_Entry.OneOf_Payload, rhs: Sinch_Chat_Sdk_V1alpha2_Entry.OneOf_Payload) -> Bool {
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

  fileprivate var _deliveryTime: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
}

struct Sinch_Chat_Sdk_V1alpha2_Channel {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var channelID: String {
    get {return _storage._channelID}
    set {_uniqueStorage()._channelID = newValue}
  }

  var displayName: String {
    get {return _storage._displayName}
    set {_uniqueStorage()._displayName = newValue}
  }

  var lastEntry: Sinch_Chat_Sdk_V1alpha2_Entry {
    get {return _storage._lastEntry ?? Sinch_Chat_Sdk_V1alpha2_Entry()}
    set {_uniqueStorage()._lastEntry = newValue}
  }
  /// Returns true if `lastEntry` has been explicitly set.
  var hasLastEntry: Bool {return _storage._lastEntry != nil}
  /// Clears the value of `lastEntry`. Subsequent reads from it will return its default value.
  mutating func clearLastEntry() {_uniqueStorage()._lastEntry = nil}

  var users: [String] {
    get {return _storage._users}
    set {_uniqueStorage()._users = newValue}
  }

  var createdAt: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _storage._createdAt ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_uniqueStorage()._createdAt = newValue}
  }
  /// Returns true if `createdAt` has been explicitly set.
  var hasCreatedAt: Bool {return _storage._createdAt != nil}
  /// Clears the value of `createdAt`. Subsequent reads from it will return its default value.
  mutating func clearCreatedAt() {_uniqueStorage()._createdAt = nil}

  var updatedAt: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _storage._updatedAt ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_uniqueStorage()._updatedAt = newValue}
  }
  /// Returns true if `updatedAt` has been explicitly set.
  var hasUpdatedAt: Bool {return _storage._updatedAt != nil}
  /// Clears the value of `updatedAt`. Subsequent reads from it will return its default value.
  mutating func clearUpdatedAt() {_uniqueStorage()._updatedAt = nil}

  var expiredAt: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _storage._expiredAt ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_uniqueStorage()._expiredAt = newValue}
  }
  /// Returns true if `expiredAt` has been explicitly set.
  var hasExpiredAt: Bool {return _storage._expiredAt != nil}
  /// Clears the value of `expiredAt`. Subsequent reads from it will return its default value.
  mutating func clearExpiredAt() {_uniqueStorage()._expiredAt = nil}

  var seenAt: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _storage._seenAt ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_uniqueStorage()._seenAt = newValue}
  }
  /// Returns true if `seenAt` has been explicitly set.
  var hasSeenAt: Bool {return _storage._seenAt != nil}
  /// Clears the value of `seenAt`. Subsequent reads from it will return its default value.
  mutating func clearSeenAt() {_uniqueStorage()._seenAt = nil}

  var status: Sinch_Chat_Sdk_V1alpha2_ChannelStatus {
    get {return _storage._status}
    set {_uniqueStorage()._status = newValue}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Chat_Sdk_V1alpha2_PushPlatform: @unchecked Sendable {}
extension Sinch_Chat_Sdk_V1alpha2_ChannelStatus: @unchecked Sendable {}
extension Sinch_Chat_Sdk_V1alpha2_Entry: @unchecked Sendable {}
extension Sinch_Chat_Sdk_V1alpha2_Entry.OneOf_Payload: @unchecked Sendable {}
extension Sinch_Chat_Sdk_V1alpha2_Channel: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.chat.sdk.v1alpha2"

extension Sinch_Chat_Sdk_V1alpha2_PushPlatform: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PLATFORM_UNSPECIFIED"),
    1: .same(proto: "WEB"),
    2: .same(proto: "IOS_SANDBOX"),
    3: .same(proto: "IOS"),
    4: .same(proto: "ANDROID"),
  ]
}

extension Sinch_Chat_Sdk_V1alpha2_ChannelStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "ChannelStatus_OPEN"),
    1: .same(proto: "ChannelStatus_CLOSED"),
  ]
}

extension Sinch_Chat_Sdk_V1alpha2_Entry: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Entry"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "delivery_time"),
    2: .standard(proto: "app_message"),
    3: .standard(proto: "app_event"),
    4: .standard(proto: "contact_message"),
    5: .standard(proto: "contact_event"),
    6: .standard(proto: "entry_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._deliveryTime) }()
      case 2: try {
        var v: Sinch_Conversationapi_Type_AppMessage?
        var hadOneofValue = false
        if let current = self.payload {
          hadOneofValue = true
          if case .appMessage(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.payload = .appMessage(v)
        }
      }()
      case 3: try {
        var v: Sinch_Conversationapi_Type_AppEvent?
        var hadOneofValue = false
        if let current = self.payload {
          hadOneofValue = true
          if case .appEvent(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.payload = .appEvent(v)
        }
      }()
      case 4: try {
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
      case 5: try {
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
      case 6: try { try decoder.decodeSingularStringField(value: &self.entryID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._deliveryTime {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    switch self.payload {
    case .appMessage?: try {
      guard case .appMessage(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .appEvent?: try {
      guard case .appEvent(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .contactMessage?: try {
      guard case .contactMessage(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    }()
    case .contactEvent?: try {
      guard case .contactEvent(let v)? = self.payload else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
    }()
    case nil: break
    }
    if !self.entryID.isEmpty {
      try visitor.visitSingularStringField(value: self.entryID, fieldNumber: 6)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Sdk_V1alpha2_Entry, rhs: Sinch_Chat_Sdk_V1alpha2_Entry) -> Bool {
    if lhs._deliveryTime != rhs._deliveryTime {return false}
    if lhs.payload != rhs.payload {return false}
    if lhs.entryID != rhs.entryID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Chat_Sdk_V1alpha2_Channel: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Channel"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "channel_id"),
    2: .standard(proto: "display_name"),
    3: .standard(proto: "last_entry"),
    4: .same(proto: "users"),
    5: .standard(proto: "created_at"),
    6: .standard(proto: "updated_at"),
    7: .standard(proto: "expired_at"),
    8: .standard(proto: "seen_at"),
    9: .same(proto: "status"),
  ]

  fileprivate class _StorageClass {
    var _channelID: String = String()
    var _displayName: String = String()
    var _lastEntry: Sinch_Chat_Sdk_V1alpha2_Entry? = nil
    var _users: [String] = []
    var _createdAt: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
    var _updatedAt: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
    var _expiredAt: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
    var _seenAt: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
    var _status: Sinch_Chat_Sdk_V1alpha2_ChannelStatus = .open

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _channelID = source._channelID
      _displayName = source._displayName
      _lastEntry = source._lastEntry
      _users = source._users
      _createdAt = source._createdAt
      _updatedAt = source._updatedAt
      _expiredAt = source._expiredAt
      _seenAt = source._seenAt
      _status = source._status
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
        case 1: try { try decoder.decodeSingularStringField(value: &_storage._channelID) }()
        case 2: try { try decoder.decodeSingularStringField(value: &_storage._displayName) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._lastEntry) }()
        case 4: try { try decoder.decodeRepeatedStringField(value: &_storage._users) }()
        case 5: try { try decoder.decodeSingularMessageField(value: &_storage._createdAt) }()
        case 6: try { try decoder.decodeSingularMessageField(value: &_storage._updatedAt) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._expiredAt) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._seenAt) }()
        case 9: try { try decoder.decodeSingularEnumField(value: &_storage._status) }()
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
      if !_storage._channelID.isEmpty {
        try visitor.visitSingularStringField(value: _storage._channelID, fieldNumber: 1)
      }
      if !_storage._displayName.isEmpty {
        try visitor.visitSingularStringField(value: _storage._displayName, fieldNumber: 2)
      }
      try { if let v = _storage._lastEntry {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      } }()
      if !_storage._users.isEmpty {
        try visitor.visitRepeatedStringField(value: _storage._users, fieldNumber: 4)
      }
      try { if let v = _storage._createdAt {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._updatedAt {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._expiredAt {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._seenAt {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
      if _storage._status != .open {
        try visitor.visitSingularEnumField(value: _storage._status, fieldNumber: 9)
      }
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Chat_Sdk_V1alpha2_Channel, rhs: Sinch_Chat_Sdk_V1alpha2_Channel) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._channelID != rhs_storage._channelID {return false}
        if _storage._displayName != rhs_storage._displayName {return false}
        if _storage._lastEntry != rhs_storage._lastEntry {return false}
        if _storage._users != rhs_storage._users {return false}
        if _storage._createdAt != rhs_storage._createdAt {return false}
        if _storage._updatedAt != rhs_storage._updatedAt {return false}
        if _storage._expiredAt != rhs_storage._expiredAt {return false}
        if _storage._seenAt != rhs_storage._seenAt {return false}
        if _storage._status != rhs_storage._status {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
