// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/channel_event_type.proto
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

enum Sinch_Conversationapi_Type_ChannelEventType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case typeUnspecified // = 0
  case whatsAppQualityRatingChanged // = 1
  case whatsAppDailyLimitChanged // = 2
  case whatsAppProductNotDeliveredWarning // = 3
  case whatsAppTemplateStatusUpdated // = 4
  case UNRECOGNIZED(Int)

  init() {
    self = .typeUnspecified
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .typeUnspecified
    case 1: self = .whatsAppQualityRatingChanged
    case 2: self = .whatsAppDailyLimitChanged
    case 3: self = .whatsAppProductNotDeliveredWarning
    case 4: self = .whatsAppTemplateStatusUpdated
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .typeUnspecified: return 0
    case .whatsAppQualityRatingChanged: return 1
    case .whatsAppDailyLimitChanged: return 2
    case .whatsAppProductNotDeliveredWarning: return 3
    case .whatsAppTemplateStatusUpdated: return 4
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ChannelEventType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_ChannelEventType] = [
    .typeUnspecified,
    .whatsAppQualityRatingChanged,
    .whatsAppDailyLimitChanged,
    .whatsAppProductNotDeliveredWarning,
    .whatsAppTemplateStatusUpdated,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ChannelEventType: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_ChannelEventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "TYPE_UNSPECIFIED"),
    1: .same(proto: "WHATS_APP_QUALITY_RATING_CHANGED"),
    2: .same(proto: "WHATS_APP_DAILY_LIMIT_CHANGED"),
    3: .same(proto: "WHATS_APP_PRODUCT_NOT_DELIVERED_WARNING"),
    4: .same(proto: "WHATS_APP_TEMPLATE_STATUS_UPDATED"),
  ]
}
