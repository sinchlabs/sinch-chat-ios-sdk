//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: sinch/chat/entry/v1alpha1/entry.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import GRPC
import NIO
import SwiftProtobuf


/// Usage: instantiate `Sinch_Chat_Entry_V1alpha1_EntryServiceClient`, then call methods of this protocol to make API calls.
internal protocol Sinch_Chat_Entry_V1alpha1_EntryServiceClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol? { get }

  func list(
    _ request: Sinch_Chat_Entry_V1alpha1_ListRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Sinch_Chat_Entry_V1alpha1_ListRequest, Sinch_Chat_Entry_V1alpha1_ListResponse>

  func create(
    _ request: Sinch_Chat_Entry_V1alpha1_CreateRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Sinch_Chat_Entry_V1alpha1_CreateRequest, Sinch_Chat_Entry_V1alpha1_Entry>
}

extension Sinch_Chat_Entry_V1alpha1_EntryServiceClientProtocol {
  internal var serviceName: String {
    return "sinch.chat.entry.v1alpha1.EntryService"
  }

  /// Unary call to List
  ///
  /// - Parameters:
  ///   - request: Request to send to List.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func list(
    _ request: Sinch_Chat_Entry_V1alpha1_ListRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Sinch_Chat_Entry_V1alpha1_ListRequest, Sinch_Chat_Entry_V1alpha1_ListResponse> {
    return self.makeUnaryCall(
      path: "/sinch.chat.entry.v1alpha1.EntryService/List",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListInterceptors() ?? []
    )
  }

  /// Unary call to Create
  ///
  /// - Parameters:
  ///   - request: Request to send to Create.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func create(
    _ request: Sinch_Chat_Entry_V1alpha1_CreateRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Sinch_Chat_Entry_V1alpha1_CreateRequest, Sinch_Chat_Entry_V1alpha1_Entry> {
    return self.makeUnaryCall(
      path: "/sinch.chat.entry.v1alpha1.EntryService/Create",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateInterceptors() ?? []
    )
  }
}

internal protocol Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol {

  /// - Returns: Interceptors to use when invoking 'list'.
  func makeListInterceptors() -> [ClientInterceptor<Sinch_Chat_Entry_V1alpha1_ListRequest, Sinch_Chat_Entry_V1alpha1_ListResponse>]

  /// - Returns: Interceptors to use when invoking 'create'.
  func makeCreateInterceptors() -> [ClientInterceptor<Sinch_Chat_Entry_V1alpha1_CreateRequest, Sinch_Chat_Entry_V1alpha1_Entry>]
}

internal final class Sinch_Chat_Entry_V1alpha1_EntryServiceClient: Sinch_Chat_Entry_V1alpha1_EntryServiceClientProtocol {
  internal let channel: GRPCChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol?

  /// Creates a client for the sinch.chat.entry.v1alpha1.EntryService service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

internal final class Sinch_Chat_Entry_V1alpha1_EntryServiceTestClient: Sinch_Chat_Entry_V1alpha1_EntryServiceClientProtocol {
  private let fakeChannel: FakeChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol?

  internal var channel: GRPCChannel {
    return self.fakeChannel
  }

  internal init(
    fakeChannel: FakeChannel = FakeChannel(),
    defaultCallOptions callOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Chat_Entry_V1alpha1_EntryServiceClientInterceptorFactoryProtocol? = nil
  ) {
    self.fakeChannel = fakeChannel
    self.defaultCallOptions = callOptions
    self.interceptors = interceptors
  }

  /// Make a unary response for the List RPC. This must be called
  /// before calling 'list'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  internal func makeListResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Chat_Entry_V1alpha1_ListRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Sinch_Chat_Entry_V1alpha1_ListRequest, Sinch_Chat_Entry_V1alpha1_ListResponse> {
    return self.fakeChannel.makeFakeUnaryResponse(path: "/sinch.chat.entry.v1alpha1.EntryService/List", requestHandler: requestHandler)
  }

  internal func enqueueListResponse(
    _ response: Sinch_Chat_Entry_V1alpha1_ListResponse,
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Chat_Entry_V1alpha1_ListRequest>) -> () = { _ in }
  )  {
    let stream = self.makeListResponseStream(requestHandler)
    // This is the only operation on the stream; try! is fine.
    try! stream.sendMessage(response)
  }

  /// Returns true if there are response streams enqueued for 'List'
  internal var hasListResponsesRemaining: Bool {
    return self.fakeChannel.hasFakeResponseEnqueued(forPath: "/sinch.chat.entry.v1alpha1.EntryService/List")
  }

  /// Make a unary response for the Create RPC. This must be called
  /// before calling 'create'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  internal func makeCreateResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Chat_Entry_V1alpha1_CreateRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Sinch_Chat_Entry_V1alpha1_CreateRequest, Sinch_Chat_Entry_V1alpha1_Entry> {
    return self.fakeChannel.makeFakeUnaryResponse(path: "/sinch.chat.entry.v1alpha1.EntryService/Create", requestHandler: requestHandler)
  }

  internal func enqueueCreateResponse(
    _ response: Sinch_Chat_Entry_V1alpha1_Entry,
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Chat_Entry_V1alpha1_CreateRequest>) -> () = { _ in }
  )  {
    let stream = self.makeCreateResponseStream(requestHandler)
    // This is the only operation on the stream; try! is fine.
    try! stream.sendMessage(response)
  }

  /// Returns true if there are response streams enqueued for 'Create'
  internal var hasCreateResponsesRemaining: Bool {
    return self.fakeChannel.hasFakeResponseEnqueued(forPath: "/sinch.chat.entry.v1alpha1.EntryService/Create")
  }
}

