// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/mt_origin.proto
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

enum Sinch_Conversationapi_Type_MtOrigin: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// MT originated from a direct message request on Conversation API 
  case directMessage // = 0

  /// MT originated from a direct batch request on Batch API 
  case directBatch // = 1

  /// MT originated from a scheduled batch request on Batch API 
  case scheduledBatch // = 2
  case UNRECOGNIZED(Int)

  init() {
    self = .directMessage
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .directMessage
    case 1: self = .directBatch
    case 2: self = .scheduledBatch
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .directMessage: return 0
    case .directBatch: return 1
    case .scheduledBatch: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_MtOrigin: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_MtOrigin] = [
    .directMessage,
    .directBatch,
    .scheduledBatch,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_MtOrigin: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_MtOrigin: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DIRECT_MESSAGE"),
    1: .same(proto: "DIRECT_BATCH"),
    2: .same(proto: "SCHEDULED_BATCH"),
  ]
}