// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/reason.proto
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

enum Sinch_Conversationapi_Type_ReasonCode: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// UNKNOWN is used if no other code can be used to describe the encountered error.
  case unknown // = 0

  /// An internal error occurred. Please save the entire callback if you want to
  /// report an error. 
  case internalError // = 1

  /// The message or event was not sent due to rate limiting.
  case rateLimited // = 2

  /// The channel recipient identity was malformed.
  case recipientInvalidChannelIdentity // = 3

  /// It was not possible to reach the contact, or channel recipient identity,
  /// on the channel. 
  case recipientNotReachable // = 4

  /// The contact, or channel recipient identity, has not opt-ed in on the channel.
  case recipientNotOptedIn // = 5

  /// The allowed sending window has expired. See the channel documentation
  /// for more information about how the sending window works for the different
  /// channels. 
  case outsideAllowedSendingWindow // = 6

  /// The channel failed to accept the message. The Conversation API performs
  /// multiple retries in case of transient errors 
  case channelFailure // = 7

  /// The configuration of the channel for the used App is wrong. The bad
  /// configuration caused the channel to reject the message. Please see
  /// the channel support documentation page for how to set it up correctly. 
  case channelBadConfiguration // = 8

  /// The configuration of the channel is missing from the used App. Please see
  /// the channel support documentation page for how to set it up correctly. 
  case channelConfigurationMissing // = 9

  /// Some of the referenced media files is of a unsupported media type. Please
  /// read the channel support documentation page to find out the limitations
  /// on media that the different channels impose. 
  case mediaTypeUnsupported // = 10

  /// Some of the referenced media files are too large. Please read the channel
  /// support documentation to find out the limitations on file size that the
  /// different channels impose. 
  case mediaTooLarge // = 11

  /// The provided media link was not accessible from the Conversation API or
  /// from the underlying channels. Please make sure that the media file is
  /// accessible. 
  case mediaNotReachable // = 12

  /// No channels to try to send the message to. This error will occur if one
  /// attempts to send a message to a channel with no channel identities or if
  /// all applicable channels have been attempted. 
  case noChannelsLeft // = 13

  /// The referenced template was not found.
  case templateNotFound // = 14

  /// Sufficient template parameters was not given. All parameters defined
  /// in the template must be provided when sending a template message 
  case templateInsufficientParameters // = 15

  /// The selected language, or version, of the referenced template did
  /// not exist. Please check the available versions and languages of the template 
  case templateNonExistingLanguageOrVersion // = 16

  /// The message delivery, or event delivery, failed due to a channel-imposed timeout.
  /// See the channel support documentation page for further details
  /// about how the different channels behave. 
  case deliveryTimedOut // = 17

  /// The message or event was rejected by the channel due to a policy.
  /// Some channels have specific policies that must be met to send a message.
  /// See the channel support documentation page for more information about
  /// when this error will be triggered. 
  case deliveryRejectedDueToPolicy // = 18

  /// The provided Contact ID did not exist.
  case contactNotFound // = 19

  /// Conversation API validates send requests in two different stages.
  /// The first stage is right before the message is enqueued.
  /// If this first validation fails the API responds with 400 Bad Request
  /// and the request is discarded immediately.
  /// The second validation kicks in during message processing and
  /// it normally contains channel specific validation rules.
  /// Failures during second request validation are
  /// delivered as callbacks to MESSAGE_DELIVERY (EVENT_DELIVERY) webhooks
  /// with ReasonCode BAD_REQUEST. 
  case badRequest // = 20

  /// The used App is missing. This error may occur when the app is removed
  /// during message processing. 
  case unknownApp // = 21

  /// The contact has no channel identities setup, or the contact has no
  /// channels setup for the resolved channel priorities. 
  case noChannelIdentityForContact // = 22

  /// Generic error for channel permanently rejecting a message.
  /// Only used if no other better matching error can be used 
  case channelReject // = 23

  /// No permission to perform action 
  case noPermission // = 24

  /// No available profile data for user 
  case noProfileAvailable // = 25

  /// Generic error for channel unsupported operations.
  case unsupportedOperation // = 26

  /// The channel configuration is in `PENDING` or `FAILING` status.
  case inactiveCredential // = 27

  /// Message is expired and will not be sent 
  case messageExpired // = 28

  /// Message is long, requires split
  case messageSplitRequired // = 29
  case UNRECOGNIZED(Int)

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .internalError
    case 2: self = .rateLimited
    case 3: self = .recipientInvalidChannelIdentity
    case 4: self = .recipientNotReachable
    case 5: self = .recipientNotOptedIn
    case 6: self = .outsideAllowedSendingWindow
    case 7: self = .channelFailure
    case 8: self = .channelBadConfiguration
    case 9: self = .channelConfigurationMissing
    case 10: self = .mediaTypeUnsupported
    case 11: self = .mediaTooLarge
    case 12: self = .mediaNotReachable
    case 13: self = .noChannelsLeft
    case 14: self = .templateNotFound
    case 15: self = .templateInsufficientParameters
    case 16: self = .templateNonExistingLanguageOrVersion
    case 17: self = .deliveryTimedOut
    case 18: self = .deliveryRejectedDueToPolicy
    case 19: self = .contactNotFound
    case 20: self = .badRequest
    case 21: self = .unknownApp
    case 22: self = .noChannelIdentityForContact
    case 23: self = .channelReject
    case 24: self = .noPermission
    case 25: self = .noProfileAvailable
    case 26: self = .unsupportedOperation
    case 27: self = .inactiveCredential
    case 28: self = .messageExpired
    case 29: self = .messageSplitRequired
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .internalError: return 1
    case .rateLimited: return 2
    case .recipientInvalidChannelIdentity: return 3
    case .recipientNotReachable: return 4
    case .recipientNotOptedIn: return 5
    case .outsideAllowedSendingWindow: return 6
    case .channelFailure: return 7
    case .channelBadConfiguration: return 8
    case .channelConfigurationMissing: return 9
    case .mediaTypeUnsupported: return 10
    case .mediaTooLarge: return 11
    case .mediaNotReachable: return 12
    case .noChannelsLeft: return 13
    case .templateNotFound: return 14
    case .templateInsufficientParameters: return 15
    case .templateNonExistingLanguageOrVersion: return 16
    case .deliveryTimedOut: return 17
    case .deliveryRejectedDueToPolicy: return 18
    case .contactNotFound: return 19
    case .badRequest: return 20
    case .unknownApp: return 21
    case .noChannelIdentityForContact: return 22
    case .channelReject: return 23
    case .noPermission: return 24
    case .noProfileAvailable: return 25
    case .unsupportedOperation: return 26
    case .inactiveCredential: return 27
    case .messageExpired: return 28
    case .messageSplitRequired: return 29
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ReasonCode: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_ReasonCode] = [
    .unknown,
    .internalError,
    .rateLimited,
    .recipientInvalidChannelIdentity,
    .recipientNotReachable,
    .recipientNotOptedIn,
    .outsideAllowedSendingWindow,
    .channelFailure,
    .channelBadConfiguration,
    .channelConfigurationMissing,
    .mediaTypeUnsupported,
    .mediaTooLarge,
    .mediaNotReachable,
    .noChannelsLeft,
    .templateNotFound,
    .templateInsufficientParameters,
    .templateNonExistingLanguageOrVersion,
    .deliveryTimedOut,
    .deliveryRejectedDueToPolicy,
    .contactNotFound,
    .badRequest,
    .unknownApp,
    .noChannelIdentityForContact,
    .channelReject,
    .noPermission,
    .noProfileAvailable,
    .unsupportedOperation,
    .inactiveCredential,
    .messageExpired,
    .messageSplitRequired,
  ]
}

#endif  // swift(>=4.2)

enum Sinch_Conversationapi_Type_ReasonSubCode: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// UNSPECIFIED_SUB_CODE is used if no other sub code can be used to describe the encountered error.
  case unspecifiedSubCode // = 0

  /// The message attachment was rejected by the channel due to a policy.
  /// Some channels have specific policies that must be met to receive an attachment. 
  case attachmentRejected // = 1

  /// The specified media urls media type could not be determined 
  case mediaTypeUndetermined // = 2

  /// The used credentials for the underlying channel is inactivated and not allowed to send or receive messages. 
  case inactiveSender // = 3
  case UNRECOGNIZED(Int)

  init() {
    self = .unspecifiedSubCode
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unspecifiedSubCode
    case 1: self = .attachmentRejected
    case 2: self = .mediaTypeUndetermined
    case 3: self = .inactiveSender
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .unspecifiedSubCode: return 0
    case .attachmentRejected: return 1
    case .mediaTypeUndetermined: return 2
    case .inactiveSender: return 3
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ReasonSubCode: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_ReasonSubCode] = [
    .unspecifiedSubCode,
    .attachmentRejected,
    .mediaTypeUndetermined,
    .inactiveSender,
  ]
}

#endif  // swift(>=4.2)

struct Sinch_Conversationapi_Type_Reason {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The code is a high-level classification of the error.
  /// UNKNOWN is used if no other code can be used to describe the encountered error. 
  var code: Sinch_Conversationapi_Type_ReasonCode = .unknown

  /// A textual description of the reason.
  var description_p: String = String()

  /// The sub code is a more detailed classification of the main error.
  /// UNSPECIFIED_SUB_CODE is used if no other sub code can be used to describe the encountered error. 
  var subCode: Sinch_Conversationapi_Type_ReasonSubCode = .unspecifiedSubCode

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ReasonCode: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_ReasonSubCode: @unchecked Sendable {}
extension Sinch_Conversationapi_Type_Reason: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_ReasonCode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "INTERNAL_ERROR"),
    2: .same(proto: "RATE_LIMITED"),
    3: .same(proto: "RECIPIENT_INVALID_CHANNEL_IDENTITY"),
    4: .same(proto: "RECIPIENT_NOT_REACHABLE"),
    5: .same(proto: "RECIPIENT_NOT_OPTED_IN"),
    6: .same(proto: "OUTSIDE_ALLOWED_SENDING_WINDOW"),
    7: .same(proto: "CHANNEL_FAILURE"),
    8: .same(proto: "CHANNEL_BAD_CONFIGURATION"),
    9: .same(proto: "CHANNEL_CONFIGURATION_MISSING"),
    10: .same(proto: "MEDIA_TYPE_UNSUPPORTED"),
    11: .same(proto: "MEDIA_TOO_LARGE"),
    12: .same(proto: "MEDIA_NOT_REACHABLE"),
    13: .same(proto: "NO_CHANNELS_LEFT"),
    14: .same(proto: "TEMPLATE_NOT_FOUND"),
    15: .same(proto: "TEMPLATE_INSUFFICIENT_PARAMETERS"),
    16: .same(proto: "TEMPLATE_NON_EXISTING_LANGUAGE_OR_VERSION"),
    17: .same(proto: "DELIVERY_TIMED_OUT"),
    18: .same(proto: "DELIVERY_REJECTED_DUE_TO_POLICY"),
    19: .same(proto: "CONTACT_NOT_FOUND"),
    20: .same(proto: "BAD_REQUEST"),
    21: .same(proto: "UNKNOWN_APP"),
    22: .same(proto: "NO_CHANNEL_IDENTITY_FOR_CONTACT"),
    23: .same(proto: "CHANNEL_REJECT"),
    24: .same(proto: "NO_PERMISSION"),
    25: .same(proto: "NO_PROFILE_AVAILABLE"),
    26: .same(proto: "UNSUPPORTED_OPERATION"),
    27: .same(proto: "INACTIVE_CREDENTIAL"),
    28: .same(proto: "MESSAGE_EXPIRED"),
    29: .same(proto: "MESSAGE_SPLIT_REQUIRED"),
  ]
}

extension Sinch_Conversationapi_Type_ReasonSubCode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNSPECIFIED_SUB_CODE"),
    1: .same(proto: "ATTACHMENT_REJECTED"),
    2: .same(proto: "MEDIA_TYPE_UNDETERMINED"),
    3: .same(proto: "INACTIVE_SENDER"),
  ]
}

extension Sinch_Conversationapi_Type_Reason: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Reason"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "code"),
    2: .same(proto: "description"),
    3: .standard(proto: "sub_code"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.code) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.description_p) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self.subCode) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.code != .unknown {
      try visitor.visitSingularEnumField(value: self.code, fieldNumber: 1)
    }
    if !self.description_p.isEmpty {
      try visitor.visitSingularStringField(value: self.description_p, fieldNumber: 2)
    }
    if self.subCode != .unspecifiedSubCode {
      try visitor.visitSingularEnumField(value: self.subCode, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_Reason, rhs: Sinch_Conversationapi_Type_Reason) -> Bool {
    if lhs.code != rhs.code {return false}
    if lhs.description_p != rhs.description_p {return false}
    if lhs.subCode != rhs.subCode {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
