// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/identity_type.proto
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

///*
/// The type of identity used in a channel: MSISDN, channel-specific ID, email, ...
enum Sinch_Conversationapi_Type_IdentityType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownIdentityType // = 0
  case channelSpecificID // = 1
  case msisdn // = 2
  case email // = 3
  case UNRECOGNIZED(Int)

  init() {
    self = .unknownIdentityType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownIdentityType
    case 1: self = .channelSpecificID
    case 2: self = .msisdn
    case 3: self = .email
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownIdentityType: return 0
    case .channelSpecificID: return 1
    case .msisdn: return 2
    case .email: return 3
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_IdentityType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static var allCases: [Sinch_Conversationapi_Type_IdentityType] = [
    .unknownIdentityType,
    .channelSpecificID,
    .msisdn,
    .email,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_IdentityType: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_IdentityType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_IDENTITY_TYPE"),
    1: .same(proto: "CHANNEL_SPECIFIC_ID"),
    2: .same(proto: "MSISDN"),
    3: .same(proto: "EMAIL"),
  ]
}
