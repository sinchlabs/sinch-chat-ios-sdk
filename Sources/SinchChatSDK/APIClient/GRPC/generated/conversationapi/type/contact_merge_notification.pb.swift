// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: sinch/conversationapi/type/contact_merge_notification.proto
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

struct Sinch_Conversationapi_Type_ContactMergeNotification {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Required. The preserved contact.
  var preservedContact: Sinch_Conversationapi_Type_Contact {
    get {return _preservedContact ?? Sinch_Conversationapi_Type_Contact()}
    set {_preservedContact = newValue}
  }
  /// Returns true if `preservedContact` has been explicitly set.
  var hasPreservedContact: Bool {return self._preservedContact != nil}
  /// Clears the value of `preservedContact`. Subsequent reads from it will return its default value.
  mutating func clearPreservedContact() {self._preservedContact = nil}

  /// Required. The deleted contact.
  var deletedContact: Sinch_Conversationapi_Type_Contact {
    get {return _deletedContact ?? Sinch_Conversationapi_Type_Contact()}
    set {_deletedContact = newValue}
  }
  /// Returns true if `deletedContact` has been explicitly set.
  var hasDeletedContact: Bool {return self._deletedContact != nil}
  /// Clears the value of `deletedContact`. Subsequent reads from it will return its default value.
  mutating func clearDeletedContact() {self._deletedContact = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _preservedContact: Sinch_Conversationapi_Type_Contact? = nil
  fileprivate var _deletedContact: Sinch_Conversationapi_Type_Contact? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sinch_Conversationapi_Type_ContactMergeNotification: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sinch.conversationapi.type"

extension Sinch_Conversationapi_Type_ContactMergeNotification: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ContactMergeNotification"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "preserved_contact"),
    2: .standard(proto: "deleted_contact"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._preservedContact) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._deletedContact) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._preservedContact {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._deletedContact {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sinch_Conversationapi_Type_ContactMergeNotification, rhs: Sinch_Conversationapi_Type_ContactMergeNotification) -> Bool {
    if lhs._preservedContact != rhs._preservedContact {return false}
    if lhs._deletedContact != rhs._deletedContact {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
