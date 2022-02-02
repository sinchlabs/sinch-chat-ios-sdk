// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/contact.proto
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

enum Sinch_Conversationapi_Type_ConversationMergeStrategy: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// merge messages of active conversations into one conversation
  case merge // = 0
  case UNRECOGNIZED(Int)

  init() {
    self = .merge
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .merge
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .merge: return 0
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ConversationMergeStrategy: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static var allCases: [Sinch_Conversationapi_Type_ConversationMergeStrategy] = [
    .merge,
  ]
}

#endif  // swift(>=4.2)

enum Sinch_Conversationapi_Type_ContactLanguage: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unspecified // = 0
  case af // = 1
  case sq // = 2
  case ar // = 3
  case az // = 4
  case bn // = 5
  case bg // = 6
  case ca // = 7
  case zh // = 8
  case zhCn // = 9
  case zhHk // = 10
  case zhTw // = 11
  case hr // = 12
  case cs // = 13
  case da // = 14
  case nl // = 15
  case en // = 16
  case enGb // = 17
  case enUs // = 18
  case et // = 19
  case fil // = 20
  case fi // = 21
  case fr // = 22
  case de // = 23
  case el // = 24
  case gu // = 25
  case ha // = 26
  case he // = 27
  case hi // = 28
  case hu // = 29
  case id // = 30
  case ga // = 31
  case it // = 32
  case ja // = 33
  case kn // = 34
  case kk // = 35
  case ko // = 36
  case lo // = 37
  case lv // = 38
  case lt // = 39
  case mk // = 40
  case ms // = 41
  case ml // = 42
  case mr // = 43
  case nb // = 44
  case fa // = 45
  case pl // = 46
  case pt // = 47
  case ptBr // = 48
  case ptPt // = 49
  case pa // = 50
  case ro // = 51
  case ru // = 52
  case sr // = 53
  case sk // = 54
  case sl // = 55
  case es // = 56
  case esAr // = 57
  case esEs // = 58
  case esMx // = 59
  case sw // = 60
  case sv // = 61
  case ta // = 62
  case te // = 63
  case th // = 64
  case tr // = 65
  case uk // = 66
  case ur // = 67
  case uz // = 68
  case vi // = 69
  case zu // = 70
  case UNRECOGNIZED(Int)

  init() {
    self = .unspecified
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unspecified
    case 1: self = .af
    case 2: self = .sq
    case 3: self = .ar
    case 4: self = .az
    case 5: self = .bn
    case 6: self = .bg
    case 7: self = .ca
    case 8: self = .zh
    case 9: self = .zhCn
    case 10: self = .zhHk
    case 11: self = .zhTw
    case 12: self = .hr
    case 13: self = .cs
    case 14: self = .da
    case 15: self = .nl
    case 16: self = .en
    case 17: self = .enGb
    case 18: self = .enUs
    case 19: self = .et
    case 20: self = .fil
    case 21: self = .fi
    case 22: self = .fr
    case 23: self = .de
    case 24: self = .el
    case 25: self = .gu
    case 26: self = .ha
    case 27: self = .he
    case 28: self = .hi
    case 29: self = .hu
    case 30: self = .id
    case 31: self = .ga
    case 32: self = .it
    case 33: self = .ja
    case 34: self = .kn
    case 35: self = .kk
    case 36: self = .ko
    case 37: self = .lo
    case 38: self = .lv
    case 39: self = .lt
    case 40: self = .mk
    case 41: self = .ms
    case 42: self = .ml
    case 43: self = .mr
    case 44: self = .nb
    case 45: self = .fa
    case 46: self = .pl
    case 47: self = .pt
    case 48: self = .ptBr
    case 49: self = .ptPt
    case 50: self = .pa
    case 51: self = .ro
    case 52: self = .ru
    case 53: self = .sr
    case 54: self = .sk
    case 55: self = .sl
    case 56: self = .es
    case 57: self = .esAr
    case 58: self = .esEs
    case 59: self = .esMx
    case 60: self = .sw
    case 61: self = .sv
    case 62: self = .ta
    case 63: self = .te
    case 64: self = .th
    case 65: self = .tr
    case 66: self = .uk
    case 67: self = .ur
    case 68: self = .uz
    case 69: self = .vi
    case 70: self = .zu
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .unspecified: return 0
    case .af: return 1
    case .sq: return 2
    case .ar: return 3
    case .az: return 4
    case .bn: return 5
    case .bg: return 6
    case .ca: return 7
    case .zh: return 8
    case .zhCn: return 9
    case .zhHk: return 10
    case .zhTw: return 11
    case .hr: return 12
    case .cs: return 13
    case .da: return 14
    case .nl: return 15
    case .en: return 16
    case .enGb: return 17
    case .enUs: return 18
    case .et: return 19
    case .fil: return 20
    case .fi: return 21
    case .fr: return 22
    case .de: return 23
    case .el: return 24
    case .gu: return 25
    case .ha: return 26
    case .he: return 27
    case .hi: return 28
    case .hu: return 29
    case .id: return 30
    case .ga: return 31
    case .it: return 32
    case .ja: return 33
    case .kn: return 34
    case .kk: return 35
    case .ko: return 36
    case .lo: return 37
    case .lv: return 38
    case .lt: return 39
    case .mk: return 40
    case .ms: return 41
    case .ml: return 42
    case .mr: return 43
    case .nb: return 44
    case .fa: return 45
    case .pl: return 46
    case .pt: return 47
    case .ptBr: return 48
    case .ptPt: return 49
    case .pa: return 50
    case .ro: return 51
    case .ru: return 52
    case .sr: return 53
    case .sk: return 54
    case .sl: return 55
    case .es: return 56
    case .esAr: return 57
    case .esEs: return 58
    case .esMx: return 59
    case .sw: return 60
    case .sv: return 61
    case .ta: return 62
    case .te: return 63
    case .th: return 64
    case .tr: return 65
    case .uk: return 66
    case .ur: return 67
    case .uz: return 68
    case .vi: return 69
    case .zu: return 70
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ContactLanguage: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static var allCases: [Sinch_Conversationapi_Type_ContactLanguage] = [
    .unspecified,
    .af,
    .sq,
    .ar,
    .az,
    .bn,
    .bg,
    .ca,
    .zh,
    .zhCn,
    .zhHk,
    .zhTw,
    .hr,
    .cs,
    .da,
    .nl,
    .en,
    .enGb,
    .enUs,
    .et,
    .fil,
    .fi,
    .fr,
    .de,
    .el,
    .gu,
    .ha,
    .he,
    .hi,
    .hu,
    .id,
    .ga,
    .it,
    .ja,
    .kn,
    .kk,
    .ko,
    .lo,
    .lv,
    .lt,
    .mk,
    .ms,
    .ml,
    .mr,
    .nb,
    .fa,
    .pl,
    .pt,
    .ptBr,
    .ptPt,
    .pa,
    .ro,
    .ru,
    .sr,
    .sk,
    .sl,
    .es,
    .esAr,
    .esEs,
    .esMx,
    .sw,
    .sv,
    .ta,
    .te,
    .th,
    .tr,
    .uk,
    .ur,
    .uz,
    .vi,
    .zu,
  ]
}

#endif  // swift(>=4.2)

/// Contact
///
/// A participant in a conversation typically representing a person.
/// It is associated with a collection of channel identities.
struct Sinch_Conversationapi_Type_Contact {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The ID of the contact.
  var id: String = String()

  /// List of channel identities.
  var channelIdentities: [Sinch_Conversationapi_Type_ChannelIdentity] = []

  /// List of channels defining the channel priority.
  var channelPriority: [Sinch_Conversationapi_Type_ConversationChannel] = []

  /// Optional. The display name. A default 'Unknown' will be assigned if left empty
  var displayName: String = String()

  /// Optional. Email of the contact.
  var email: String = String()

  /// Optional. Contact identifier in an external system.
  var externalID: String = String()

  /// Optional. Metadata associated with the contact.
  /// Up to 1024 characters long. 
  var metadata: String = String()

  /// 2 letter ISO 639 language code for the contact. Default value is UNSPECIFIED language.
  var language: Sinch_Conversationapi_Type_ContactLanguage = .unspecified

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Channel Identity
///
/// A unique identity of message recipient on a particular channel.
/// For example, the channel identity on SMS, WHATSAPP or VIBERBM is a MSISDN phone number.
struct Sinch_Conversationapi_Type_ChannelIdentity {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The channel.
  var channel: Sinch_Conversationapi_Type_ConversationChannel = .channelUnspecified

  /// Required. The channel identity e.g., a phone number for SMS, WhatsApp and Viber Business.
  var identity: String = String()

  /// Optional. The Conversation API's app ID if this is app-scoped channel identity.
  /// Currently, FB Messenger and Viber are using app-scoped channel identities
  /// which means contacts will have different channel identities for different
  /// apps. FB Messenger uses PSIDs (Page-Scoped IDs) as channel identities.
  /// The app_id is pointing to the app linked to the FB page for which this PSID is issued.
  var appID: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_ConversationMergeStrategy: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "MERGE"),
  ]
}

extension Sinch_Conversationapi_Type_ContactLanguage: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNSPECIFIED"),
    1: .same(proto: "AF"),
    2: .same(proto: "SQ"),
    3: .same(proto: "AR"),
    4: .same(proto: "AZ"),
    5: .same(proto: "BN"),
    6: .same(proto: "BG"),
    7: .same(proto: "CA"),
    8: .same(proto: "ZH"),
    9: .same(proto: "ZH_CN"),
    10: .same(proto: "ZH_HK"),
    11: .same(proto: "ZH_TW"),
    12: .same(proto: "HR"),
    13: .same(proto: "CS"),
    14: .same(proto: "DA"),
    15: .same(proto: "NL"),
    16: .same(proto: "EN"),
    17: .same(proto: "EN_GB"),
    18: .same(proto: "EN_US"),
    19: .same(proto: "ET"),
    20: .same(proto: "FIL"),
    21: .same(proto: "FI"),
    22: .same(proto: "FR"),
    23: .same(proto: "DE"),
    24: .same(proto: "EL"),
    25: .same(proto: "GU"),
    26: .same(proto: "HA"),
    27: .same(proto: "HE"),
    28: .same(proto: "HI"),
    29: .same(proto: "HU"),
    30: .same(proto: "ID"),
    31: .same(proto: "GA"),
    32: .same(proto: "IT"),
    33: .same(proto: "JA"),
    34: .same(proto: "KN"),
    35: .same(proto: "KK"),
    36: .same(proto: "KO"),
    37: .same(proto: "LO"),
    38: .same(proto: "LV"),
    39: .same(proto: "LT"),
    40: .same(proto: "MK"),
    41: .same(proto: "MS"),
    42: .same(proto: "ML"),
    43: .same(proto: "MR"),
    44: .same(proto: "NB"),
    45: .same(proto: "FA"),
    46: .same(proto: "PL"),
    47: .same(proto: "PT"),
    48: .same(proto: "PT_BR"),
    49: .same(proto: "PT_PT"),
    50: .same(proto: "PA"),
    51: .same(proto: "RO"),
    52: .same(proto: "RU"),
    53: .same(proto: "SR"),
    54: .same(proto: "SK"),
    55: .same(proto: "SL"),
    56: .same(proto: "ES"),
    57: .same(proto: "ES_AR"),
    58: .same(proto: "ES_ES"),
    59: .same(proto: "ES_MX"),
    60: .same(proto: "SW"),
    61: .same(proto: "SV"),
    62: .same(proto: "TA"),
    63: .same(proto: "TE"),
    64: .same(proto: "TH"),
    65: .same(proto: "TR"),
    66: .same(proto: "UK"),
    67: .same(proto: "UR"),
    68: .same(proto: "UZ"),
    69: .same(proto: "VI"),
    70: .same(proto: "ZU"),
  ]
}

extension Sinch_Conversationapi_Type_Contact: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Contact"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .standard(proto: "channel_identities"),
    3: .standard(proto: "channel_priority"),
    4: .standard(proto: "display_name"),
    5: .same(proto: "email"),
    6: .standard(proto: "external_id"),
    7: .same(proto: "metadata"),
    8: .same(proto: "language"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.id) }()
      case 2: try { try decoder.decodeRepeatedMessageField(value: &self.channelIdentities) }()
      case 3: try { try decoder.decodeRepeatedEnumField(value: &self.channelPriority) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.displayName) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.email) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self.externalID) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self.metadata) }()
      case 8: try { try decoder.decodeSingularEnumField(value: &self.language) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.id.isEmpty {
      try visitor.visitSingularStringField(value: self.id, fieldNumber: 1)
    }
    if !self.channelIdentities.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.channelIdentities, fieldNumber: 2)
    }
    if !self.channelPriority.isEmpty {
      try visitor.visitPackedEnumField(value: self.channelPriority, fieldNumber: 3)
    }
    if !self.displayName.isEmpty {
      try visitor.visitSingularStringField(value: self.displayName, fieldNumber: 4)
    }
    if !self.email.isEmpty {
      try visitor.visitSingularStringField(value: self.email, fieldNumber: 5)
    }
    if !self.externalID.isEmpty {
      try visitor.visitSingularStringField(value: self.externalID, fieldNumber: 6)
    }
    if !self.metadata.isEmpty {
      try visitor.visitSingularStringField(value: self.metadata, fieldNumber: 7)
    }
    if self.language != .unspecified {
      try visitor.visitSingularEnumField(value: self.language, fieldNumber: 8)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_Contact, rhs: Sinch_Conversationapi_Type_Contact) -> Bool {
    if lhs.id != rhs.id {return false}
    if lhs.channelIdentities != rhs.channelIdentities {return false}
    if lhs.channelPriority != rhs.channelPriority {return false}
    if lhs.displayName != rhs.displayName {return false}
    if lhs.email != rhs.email {return false}
    if lhs.externalID != rhs.externalID {return false}
    if lhs.metadata != rhs.metadata {return false}
    if lhs.language != rhs.language {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sinch_Conversationapi_Type_ChannelIdentity: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ChannelIdentity"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channel"),
    2: .same(proto: "identity"),
    3: .standard(proto: "app_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.channel) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.identity) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.appID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.channel != .channelUnspecified {
      try visitor.visitSingularEnumField(value: self.channel, fieldNumber: 1)
    }
    if !self.identity.isEmpty {
      try visitor.visitSingularStringField(value: self.identity, fieldNumber: 2)
    }
    if !self.appID.isEmpty {
      try visitor.visitSingularStringField(value: self.appID, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_ChannelIdentity, rhs: Sinch_Conversationapi_Type_ChannelIdentity) -> Bool {
    if lhs.channel != rhs.channel {return false}
    if lhs.identity != rhs.identity {return false}
    if lhs.appID != rhs.appID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
