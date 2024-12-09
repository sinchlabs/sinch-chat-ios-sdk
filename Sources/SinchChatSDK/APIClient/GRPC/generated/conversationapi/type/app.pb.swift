// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/app.proto
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

enum Sinch_Conversationapi_Type_ConversationMetadataReportView: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// Omit metadata
  case none // = 0

  /// Include all metadata assigned to the conversation
  case full // = 1
  case UNRECOGNIZED(Int)

  init() {
    self = .none
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .none
    case 1: self = .full
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .none: return 0
    case .full: return 1
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ConversationMetadataReportView: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_ConversationMetadataReportView] = [
    .none,
    .full,
  ]
}

#endif  // swift(>=4.2)

enum Sinch_Conversationapi_Type_RetentionPolicyType: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// The default retention policy where messages older than
  /// `ttl_days` are automatically deleted from Conversation API database. 
  case messageExpirePolicy // = 0

  /// The conversation expire policy only considers the last message in a conversation.
  /// If the last message is older that `ttl_days` the entire conversation is deleted.
  /// The difference with `MESSAGE_EXPIRE_POLICY` is that messages with `accept_time`
  /// older than `ttl_days` are persisted as long as there is a newer message in the
  /// same conversation. 
  case conversationExpirePolicy // = 1

  /// Persist policy does not delete old messages or conversations.
  /// Please note that message storage might be subject to additional charges
  /// in the future. 
  case persistRetentionPolicy // = 2
  case UNRECOGNIZED(Int)

  init() {
    self = .messageExpirePolicy
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .messageExpirePolicy
    case 1: self = .conversationExpirePolicy
    case 2: self = .persistRetentionPolicy
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .messageExpirePolicy: return 0
    case .conversationExpirePolicy: return 1
    case .persistRetentionPolicy: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_RetentionPolicyType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_RetentionPolicyType] = [
    .messageExpirePolicy,
    .conversationExpirePolicy,
    .persistRetentionPolicy,
  ]
}

#endif  // swift(>=4.2)

/// Conversation API app
///
/// The app corresponds to the API user and is a collection of channel credentials
/// allowing access to the underlying messaging channels.
/// The app is tied to a set of webhooks which define the destination for various events coming from the Conversation API.
struct Sinch_Conversationapi_Type_App {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The ID of the app.
  var id: String {
    get {return _storage._id}
    set {_uniqueStorage()._id = newValue}
  }

  /// Channel credentials.
  /// The order of the credentials defines the
  /// app channel priority. 
  var channelCredentials: [Sinch_Conversationapi_Type_ConversationChannelCredential] {
    get {return _storage._channelCredentials}
    set {_uniqueStorage()._channelCredentials = newValue}
  }

  /// Optional. A flag specifying whether to return conversation metadata as
  /// part of each callback. If omitted `NONE` will be used. 
  var conversationMetadataReportView: Sinch_Conversationapi_Type_ConversationMetadataReportView {
    get {return _storage._conversationMetadataReportView}
    set {_uniqueStorage()._conversationMetadataReportView = newValue}
  }

  /// Required. Human readable identifier of the app. E.g. Sinch Conversation API Demo App 001.
  var displayName: String {
    get {return _storage._displayName}
    set {_uniqueStorage()._displayName = newValue}
  }

  /// Output only. Rate limits associated with the app. Contact your account manager to change these.
  var rateLimits: Sinch_Conversationapi_Type_RateLimits {
    get {return _storage._rateLimits ?? Sinch_Conversationapi_Type_RateLimits()}
    set {_uniqueStorage()._rateLimits = newValue}
  }
  /// Returns true if `rateLimits` has been explicitly set.
  var hasRateLimits: Bool {return _storage._rateLimits != nil}
  /// Clears the value of `rateLimits`. Subsequent reads from it will return its default value.
  mutating func clearRateLimits() {_uniqueStorage()._rateLimits = nil}

  /// Optional. Defines the retention policy for messages and conversations.
  var retentionPolicy: Sinch_Conversationapi_Type_RetentionPolicy {
    get {return _storage._retentionPolicy ?? Sinch_Conversationapi_Type_RetentionPolicy()}
    set {_uniqueStorage()._retentionPolicy = newValue}
  }
  /// Returns true if `retentionPolicy` has been explicitly set.
  var hasRetentionPolicy: Bool {return _storage._retentionPolicy != nil}
  /// Clears the value of `retentionPolicy`. Subsequent reads from it will return its default value.
  mutating func clearRetentionPolicy() {_uniqueStorage()._retentionPolicy = nil}

  /// Optional.
  /// Defines the retention policy for messages in `DISPATCH` mode.
  /// For `DISPATCH` mode, only `MESSAGE_EXPIRE_POLICY` is available and the available range for the `ttl_days` field is from 0 to 7. 
  var dispatchRetentionPolicy: Sinch_Conversationapi_Type_RetentionPolicy {
    get {return _storage._dispatchRetentionPolicy ?? Sinch_Conversationapi_Type_RetentionPolicy()}
    set {_uniqueStorage()._dispatchRetentionPolicy = newValue}
  }
  /// Returns true if `dispatchRetentionPolicy` has been explicitly set.
  var hasDispatchRetentionPolicy: Bool {return _storage._dispatchRetentionPolicy != nil}
  /// Clears the value of `dispatchRetentionPolicy`. Subsequent reads from it will return its default value.
  mutating func clearDispatchRetentionPolicy() {_uniqueStorage()._dispatchRetentionPolicy = nil}

  /// Optional.
  /// Contacts and Conversations will not be stored in database if the mode is set to `DISPATCH`.
  /// Default `processing_mode` is `CONVERSATION`, which creates Contacts and Conversations when a
  /// message is sent or received. 
  var processingMode: Sinch_Conversationapi_Type_ProcessingMode {
    get {return _storage._processingMode}
    set {_uniqueStorage()._processingMode = newValue}
  }

  /// Optional. Smart conversation configuration for app.
  var smartConversation: Sinch_Conversationapi_Type_SmartConversation {
    get {return _storage._smartConversation ?? Sinch_Conversationapi_Type_SmartConversation()}
    set {_uniqueStorage()._smartConversation = newValue}
  }
  /// Returns true if `smartConversation` has been explicitly set.
  var hasSmartConversation: Bool {return _storage._smartConversation != nil}
  /// Clears the value of `smartConversation`. Subsequent reads from it will return its default value.
  mutating func clearSmartConversation() {_uniqueStorage()._smartConversation = nil}

  /// Output only. Current size and limit of the app queues.
  var queueStats: Sinch_Conversationapi_Type_QueueStats {
    get {return _storage._queueStats ?? Sinch_Conversationapi_Type_QueueStats()}
    set {_uniqueStorage()._queueStats = newValue}
  }
  /// Returns true if `queueStats` has been explicitly set.
  var hasQueueStats: Bool {return _storage._queueStats != nil}
  /// Clears the value of `queueStats`. Subsequent reads from it will return its default value.
  mutating func clearQueueStats() {_uniqueStorage()._queueStats = nil}

  ///Optional. Message status persistence configuration.
  var persistMessageStatus: Sinch_Conversationapi_Type_PersistMessageStatus {
    get {return _storage._persistMessageStatus ?? Sinch_Conversationapi_Type_PersistMessageStatus()}
    set {_uniqueStorage()._persistMessageStatus = newValue}
  }
  /// Returns true if `persistMessageStatus` has been explicitly set.
  var hasPersistMessageStatus: Bool {return _storage._persistMessageStatus != nil}
  /// Clears the value of `persistMessageStatus`. Subsequent reads from it will return its default value.
  mutating func clearPersistMessageStatus() {_uniqueStorage()._persistMessageStatus = nil}

  ///Optional. Message search configuration.
  var messageSearch: Sinch_Conversationapi_Type_MessageSearch {
    get {return _storage._messageSearch ?? Sinch_Conversationapi_Type_MessageSearch()}
    set {_uniqueStorage()._messageSearch = newValue}
  }
  /// Returns true if `messageSearch` has been explicitly set.
  var hasMessageSearch: Bool {return _storage._messageSearch != nil}
  /// Clears the value of `messageSearch`. Subsequent reads from it will return its default value.
  mutating func clearMessageSearch() {_uniqueStorage()._messageSearch = nil}

  ///Optional. Additional callback configuration.
  var callbackSettings: Sinch_Conversationapi_Type_CallbackSettings {
    get {return _storage._callbackSettings ?? Sinch_Conversationapi_Type_CallbackSettings()}
    set {_uniqueStorage()._callbackSettings = newValue}
  }
  /// Returns true if `callbackSettings` has been explicitly set.
  var hasCallbackSettings: Bool {return _storage._callbackSettings != nil}
  /// Clears the value of `callbackSettings`. Subsequent reads from it will return its default value.
  mutating func clearCallbackSettings() {_uniqueStorage()._callbackSettings = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

struct Sinch_Conversationapi_Type_RateLimits {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Output only. The number of messages/events we process per second, from the
  /// app to the underlying channels. Note that underlying channels may have other
  /// rate limits.  The default rate limit is 25.
  var outbound: UInt32 = 0

  /// Output only. The number of inbound messages/events we process per second,
  /// from underlying channels to the app.  The default rate limit is 25.
  var inbound: UInt32 = 0

  /// Output only. The rate limit of callbacks sent to the webhooks registered
  /// for the app. Note that if you have multiple webhooks with shared triggers,
  /// multiple callbacks will be sent out for each triggering event. The default rate limit is 25.
  var webhooks: UInt32 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Retention policy for messages and conversations
struct Sinch_Conversationapi_Type_RetentionPolicy {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. Whether or not old messages or conversations are automatically deleted. 
  var retentionType: Sinch_Conversationapi_Type_RetentionPolicyType = .messageExpirePolicy

  /// Optional. The days before a message or conversation is eligible for deletion.
  /// Default value is 180. The `ttl_days` value has no effect when `retention_type`
  /// is `PERSIST_RETENTION_POLICY`. The valid values for this field are [1 - 3650].
  /// Note that retention cleanup job runs once every twenty-four hours
  /// which can lead to delay i.e., messages and conversations are not deleted on
  /// the minute they become eligible for deletion. 
  var ttlDays: UInt32 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Smart conversation configuration for app.
struct Sinch_Conversationapi_Type_SmartConversation {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. A flag specifying whether this app has subscribed to Smart conversation services 
  var enabled: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Type_QueueStats {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var outboundSize: UInt32 = 0

  var outboundLimit: UInt32 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Type_PersistFailedMessages {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. A flag specifying whether failed messages for this app should be persisted 
  var enabled: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sinch_Conversationapi_Type_PersistMessageStatus {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. A flag specifying whether message status for this app should be persisted 
  var enabled: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Message search configuration.
struct Sinch_Conversationapi_Type_MessageSearch {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. A flag specifying whether this app has enabled Message Search services 
  var enabled: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Additional callback configuration.
struct Sinch_Conversationapi_Type_CallbackSettings {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Optional. Secret can be used to sign contents of delivery receipts for a message that was sent with the default "callback_url" overridden.
  /// You can then use the secret to verify the signature. 
  var secretForOverriddenCallbackUrls: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ConversationMetadataReportView: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_RetentionPolicyType: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_App: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_RateLimits: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_RetentionPolicy: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_SmartConversation: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_QueueStats: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_PersistFailedMessages: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_PersistMessageStatus: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_MessageSearch: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_CallbackSettings: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_ConversationMetadataReportView: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "NONE"),
    1: .same(proto: "FULL"),
  ]
}

extension Sinch_Conversationapi_Type_RetentionPolicyType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "MESSAGE_EXPIRE_POLICY"),
    1: .same(proto: "CONVERSATION_EXPIRE_POLICY"),
    2: .same(proto: "PERSIST_RETENTION_POLICY"),
  ]
}

extension Sinch_Conversationapi_Type_App: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".App"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .standard(proto: "channel_credentials"),
    3: .standard(proto: "conversation_metadata_report_view"),
    4: .standard(proto: "display_name"),
    5: .standard(proto: "rate_limits"),
    6: .standard(proto: "retention_policy"),
    7: .standard(proto: "dispatch_retention_policy"),
    8: .standard(proto: "processing_mode"),
    9: .standard(proto: "smart_conversation"),
    10: .standard(proto: "queue_stats"),
    11: .standard(proto: "persist_message_status"),
    12: .standard(proto: "message_search"),
    13: .standard(proto: "callback_settings"),
  ]

  fileprivate class _StorageClass {
    var _id: String = String()
    var _channelCredentials: [Sinch_Conversationapi_Type_ConversationChannelCredential] = []
    var _conversationMetadataReportView: Sinch_Conversationapi_Type_ConversationMetadataReportView = .none
    var _displayName: String = String()
    var _rateLimits: Sinch_Conversationapi_Type_RateLimits? = nil
    var _retentionPolicy: Sinch_Conversationapi_Type_RetentionPolicy? = nil
    var _dispatchRetentionPolicy: Sinch_Conversationapi_Type_RetentionPolicy? = nil
    var _processingMode: Sinch_Conversationapi_Type_ProcessingMode = .conversation
    var _smartConversation: Sinch_Conversationapi_Type_SmartConversation? = nil
    var _queueStats: Sinch_Conversationapi_Type_QueueStats? = nil
    var _persistMessageStatus: Sinch_Conversationapi_Type_PersistMessageStatus? = nil
    var _messageSearch: Sinch_Conversationapi_Type_MessageSearch? = nil
    var _callbackSettings: Sinch_Conversationapi_Type_CallbackSettings? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _id = source._id
      _channelCredentials = source._channelCredentials
      _conversationMetadataReportView = source._conversationMetadataReportView
      _displayName = source._displayName
      _rateLimits = source._rateLimits
      _retentionPolicy = source._retentionPolicy
      _dispatchRetentionPolicy = source._dispatchRetentionPolicy
      _processingMode = source._processingMode
      _smartConversation = source._smartConversation
      _queueStats = source._queueStats
      _persistMessageStatus = source._persistMessageStatus
      _messageSearch = source._messageSearch
      _callbackSettings = source._callbackSettings
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
        case 1: try { try decoder.decodeSingularStringField(value: &_storage._id) }()
        case 2: try { try decoder.decodeRepeatedMessageField(value: &_storage._channelCredentials) }()
        case 3: try { try decoder.decodeSingularEnumField(value: &_storage._conversationMetadataReportView) }()
        case 4: try { try decoder.decodeSingularStringField(value: &_storage._displayName) }()
        case 5: try { try decoder.decodeSingularMessageField(value: &_storage._rateLimits) }()
        case 6: try { try decoder.decodeSingularMessageField(value: &_storage._retentionPolicy) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._dispatchRetentionPolicy) }()
        case 8: try { try decoder.decodeSingularEnumField(value: &_storage._processingMode) }()
        case 9: try { try decoder.decodeSingularMessageField(value: &_storage._smartConversation) }()
        case 10: try { try decoder.decodeSingularMessageField(value: &_storage._queueStats) }()
        case 11: try { try decoder.decodeSingularMessageField(value: &_storage._persistMessageStatus) }()
        case 12: try { try decoder.decodeSingularMessageField(value: &_storage._messageSearch) }()
        case 13: try { try decoder.decodeSingularMessageField(value: &_storage._callbackSettings) }()
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
      if !_storage._id.isEmpty {
        try visitor.visitSingularStringField(value: _storage._id, fieldNumber: 1)
      }
      if !_storage._channelCredentials.isEmpty {
        try visitor.visitRepeatedMessageField(value: _storage._channelCredentials, fieldNumber: 2)
      }
      if _storage._conversationMetadataReportView != .none {
        try visitor.visitSingularEnumField(value: _storage._conversationMetadataReportView, fieldNumber: 3)
      }
      if !_storage._displayName.isEmpty {
        try visitor.visitSingularStringField(value: _storage._displayName, fieldNumber: 4)
      }
      try { if let v = _storage._rateLimits {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._retentionPolicy {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._dispatchRetentionPolicy {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      if _storage._processingMode != .conversation {
        try visitor.visitSingularEnumField(value: _storage._processingMode, fieldNumber: 8)
      }
      try { if let v = _storage._smartConversation {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._queueStats {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 10)
      } }()
      try { if let v = _storage._persistMessageStatus {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
      } }()
      try { if let v = _storage._messageSearch {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      } }()
      try { if let v = _storage._callbackSettings {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 13)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_App, rhs: Sinch_Conversationapi_Type_App) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._id != rhs_storage._id {return false}
        if _storage._channelCredentials != rhs_storage._channelCredentials {return false}
        if _storage._conversationMetadataReportView != rhs_storage._conversationMetadataReportView {return false}
        if _storage._displayName != rhs_storage._displayName {return false}
        if _storage._rateLimits != rhs_storage._rateLimits {return false}
        if _storage._retentionPolicy != rhs_storage._retentionPolicy {return false}
        if _storage._dispatchRetentionPolicy != rhs_storage._dispatchRetentionPolicy {return false}
        if _storage._processingMode != rhs_storage._processingMode {return false}
        if _storage._smartConversation != rhs_storage._smartConversation {return false}
        if _storage._queueStats != rhs_storage._queueStats {return false}
        if _storage._persistMessageStatus != rhs_storage._persistMessageStatus {return false}
        if _storage._messageSearch != rhs_storage._messageSearch {return false}
        if _storage._callbackSettings != rhs_storage._callbackSettings {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_RateLimits: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".RateLimits"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "outbound"),
    2: .same(proto: "inbound"),
    3: .same(proto: "webhooks"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.outbound) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self.inbound) }()
      case 3: try { try decoder.decodeSingularUInt32Field(value: &self.webhooks) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.outbound != 0 {
      try visitor.visitSingularUInt32Field(value: self.outbound, fieldNumber: 1)
    }
    if self.inbound != 0 {
      try visitor.visitSingularUInt32Field(value: self.inbound, fieldNumber: 2)
    }
    if self.webhooks != 0 {
      try visitor.visitSingularUInt32Field(value: self.webhooks, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_RateLimits, rhs: Sinch_Conversationapi_Type_RateLimits) -> Bool {
    if lhs.outbound != rhs.outbound {return false}
    if lhs.inbound != rhs.inbound {return false}
    if lhs.webhooks != rhs.webhooks {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_RetentionPolicy: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".RetentionPolicy"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "retention_type"),
    2: .standard(proto: "ttl_days"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.retentionType) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self.ttlDays) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.retentionType != .messageExpirePolicy {
      try visitor.visitSingularEnumField(value: self.retentionType, fieldNumber: 1)
    }
    if self.ttlDays != 0 {
      try visitor.visitSingularUInt32Field(value: self.ttlDays, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_RetentionPolicy, rhs: Sinch_Conversationapi_Type_RetentionPolicy) -> Bool {
    if lhs.retentionType != rhs.retentionType {return false}
    if lhs.ttlDays != rhs.ttlDays {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_SmartConversation: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SmartConversation"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "enabled"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.enabled) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.enabled != false {
      try visitor.visitSingularBoolField(value: self.enabled, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_SmartConversation, rhs: Sinch_Conversationapi_Type_SmartConversation) -> Bool {
    if lhs.enabled != rhs.enabled {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_QueueStats: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".QueueStats"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "outbound_size"),
    2: .standard(proto: "outbound_limit"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.outboundSize) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self.outboundLimit) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.outboundSize != 0 {
      try visitor.visitSingularUInt32Field(value: self.outboundSize, fieldNumber: 1)
    }
    if self.outboundLimit != 0 {
      try visitor.visitSingularUInt32Field(value: self.outboundLimit, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_QueueStats, rhs: Sinch_Conversationapi_Type_QueueStats) -> Bool {
    if lhs.outboundSize != rhs.outboundSize {return false}
    if lhs.outboundLimit != rhs.outboundLimit {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_PersistFailedMessages: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PersistFailedMessages"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "enabled"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.enabled) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.enabled != false {
      try visitor.visitSingularBoolField(value: self.enabled, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_PersistFailedMessages, rhs: Sinch_Conversationapi_Type_PersistFailedMessages) -> Bool {
    if lhs.enabled != rhs.enabled {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_PersistMessageStatus: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PersistMessageStatus"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "enabled"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.enabled) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.enabled != false {
      try visitor.visitSingularBoolField(value: self.enabled, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_PersistMessageStatus, rhs: Sinch_Conversationapi_Type_PersistMessageStatus) -> Bool {
    if lhs.enabled != rhs.enabled {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_MessageSearch: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".MessageSearch"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "enabled"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.enabled) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.enabled != false {
      try visitor.visitSingularBoolField(value: self.enabled, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_MessageSearch, rhs: Sinch_Conversationapi_Type_MessageSearch) -> Bool {
    if lhs.enabled != rhs.enabled {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_CallbackSettings: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".CallbackSettings"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "secret_for_overridden_callback_urls"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.secretForOverriddenCallbackUrls) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.secretForOverriddenCallbackUrls.isEmpty {
      try visitor.visitSingularStringField(value: self.secretForOverriddenCallbackUrls, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_CallbackSettings, rhs: Sinch_Conversationapi_Type_CallbackSettings) -> Bool {
    if lhs.secretForOverriddenCallbackUrls != rhs.secretForOverriddenCallbackUrls {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
