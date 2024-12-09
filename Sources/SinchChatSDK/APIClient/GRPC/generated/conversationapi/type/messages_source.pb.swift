// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/messages_source.proto
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

enum Sinch_Conversationapi_Type_MessagesSource: SwiftProtobuf.Enum {
  typealias RawValue = Int

  /// The default messages source.
  /// It refers to messages that were sent in the default 'CONVERSATION' processing mode,
  ///thanks to which the messages are associated with a specific conversation and a contact.
  case conversationSource // = 0

  /// It refers to messages that were sent in the 'DISPATCH' processing mode.
  /// These types of messages are not associated with any conversation or contact.
  case dispatchSource // = 1
  case UNRECOGNIZED(Int)

  init() {
    self = .conversationSource
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .conversationSource
    case 1: self = .dispatchSource
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .conversationSource: return 0
    case .dispatchSource: return 1
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Sinch_Conversationapi_Type_MessagesSource: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Sinch_Conversationapi_Type_MessagesSource] = [
    .conversationSource,
    .dispatchSource,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_MessagesSource: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Sinch_Conversationapi_Type_MessagesSource: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONVERSATION_SOURCE"),
    1: .same(proto: "DISPATCH_SOURCE"),
  ]
}
