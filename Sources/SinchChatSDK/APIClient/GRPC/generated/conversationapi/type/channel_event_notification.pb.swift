// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/channel_event_notification.proto
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

struct Sinch_Conversationapi_Type_ChannelEventNotification {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The direct event originated from the channel
  var channelEvent: SwiftProtobuf.Google_Protobuf_Struct {
    get {return _channelEvent ?? SwiftProtobuf.Google_Protobuf_Struct()}
    set {_channelEvent = newValue}
  }
  /// Returns true if `channelEvent` has been explicitly set.
  var hasChannelEvent: Bool {return self._channelEvent != nil}
  /// Clears the value of `channelEvent`. Subsequent reads from it will return its default value.
  mutating func clearChannelEvent() {self._channelEvent = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _channelEvent: SwiftProtobuf.Google_Protobuf_Struct? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ChannelEventNotification: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_ChannelEventNotification: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ChannelEventNotification"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "channel_event"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._channelEvent) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._channelEvent {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_ChannelEventNotification, rhs: Sinch_Conversationapi_Type_ChannelEventNotification) -> Bool {
    if lhs._channelEvent != rhs._channelEvent {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
