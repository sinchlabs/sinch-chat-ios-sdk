// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/processing_strategy.proto
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

enum Sinch_Conversationapi_Type_ProcessingStrategy: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// Default processing strategy. The user-defined processing mode of the app will be applied. 
  case `default` // = 0

  /// Forces the request to be processed in dispatch mode (without creating contacts or conversations)
  /// regardless of the processing mode in which the app is currently running. 
  case dispatchOnly // = 1
  case UNRECOGNIZED(Int)

  init() {
    self = .default
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .default
    case 1: self = .dispatchOnly
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .default: return 0
    case .dispatchOnly: return 1
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_ProcessingStrategy: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_ProcessingStrategy] = [
    .default,
    .dispatchOnly,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ProcessingStrategy: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_ProcessingStrategy: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DEFAULT"),
    1: .same(proto: "DISPATCH_ONLY"),
  ]
}