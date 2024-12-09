// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/metadata_update_strategy.proto
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

enum Sinch_Conversationapi_Type_MetadataUpdateStrategy: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// Default, backwards compatible implementation
  case replace // = 0

  /// MERGE_PATCH implementation conforms to RFC 7386 - JSON Merge Patch
  case mergePatch // = 1
  case UNRECOGNIZED(Int)

  init() {
    self = .replace
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .replace
    case 1: self = .mergePatch
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .replace: return 0
    case .mergePatch: return 1
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_MetadataUpdateStrategy: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_MetadataUpdateStrategy] = [
    .replace,
    .mergePatch,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_MetadataUpdateStrategy: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_MetadataUpdateStrategy: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "REPLACE"),
    1: .same(proto: "MERGE_PATCH"),
  ]
}
