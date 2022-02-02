//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: sinch/conversationapi/adapter/v1beta/channel_credential_service.proto
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


/// Allows management of channel credential via adapters.
///
/// Usage: instantiate `Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClient`, then call methods of this protocol to make API calls.
internal protocol Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol? { get }

  func getChannelCredential(
    _ request: Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialResponse>

  func setChannelCredential(
    _ request: Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialResponse>
}

extension Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientProtocol {
  internal var serviceName: String {
    return "sinch.conversationapi.adapter.v1beta.ChannelCredential"
  }

  /// Get specific channel credential by appId or channelKnownId.
  ///
  /// - Parameters:
  ///   - request: Request to send to GetChannelCredential.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func getChannelCredential(
    _ request: Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialResponse> {
    return self.makeUnaryCall(
      path: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/GetChannelCredential",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetChannelCredentialInterceptors() ?? []
    )
  }

  /// Set specific channel credential. Performs an upsert operation
  ///
  /// - Parameters:
  ///   - request: Request to send to SetChannelCredential.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func setChannelCredential(
    _ request: Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialResponse> {
    return self.makeUnaryCall(
      path: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/SetChannelCredential",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSetChannelCredentialInterceptors() ?? []
    )
  }
}

internal protocol Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol {

  /// - Returns: Interceptors to use when invoking 'getChannelCredential'.
  func makeGetChannelCredentialInterceptors() -> [ClientInterceptor<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialResponse>]

  /// - Returns: Interceptors to use when invoking 'setChannelCredential'.
  func makeSetChannelCredentialInterceptors() -> [ClientInterceptor<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialResponse>]
}

internal final class Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClient: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientProtocol {
  internal let channel: GRPCChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol?

  /// Creates a client for the sinch.conversationapi.adapter.v1beta.ChannelCredential service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

internal final class Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialTestClient: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientProtocol {
  private let fakeChannel: FakeChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol?

  internal var channel: GRPCChannel {
    return self.fakeChannel
  }

  internal init(
    fakeChannel: FakeChannel = FakeChannel(),
    defaultCallOptions callOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Conversationapi_Adapter_V1beta_ChannelCredentialClientInterceptorFactoryProtocol? = nil
  ) {
    self.fakeChannel = fakeChannel
    self.defaultCallOptions = callOptions
    self.interceptors = interceptors
  }

  /// Make a unary response for the GetChannelCredential RPC. This must be called
  /// before calling 'getChannelCredential'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  internal func makeGetChannelCredentialResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialResponse> {
    return self.fakeChannel.makeFakeUnaryResponse(path: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/GetChannelCredential", requestHandler: requestHandler)
  }

  internal func enqueueGetChannelCredentialResponse(
    _ response: Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialResponse,
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Adapter_V1beta_GetChannelCredentialRequest>) -> () = { _ in }
  )  {
    let stream = self.makeGetChannelCredentialResponseStream(requestHandler)
    // This is the only operation on the stream; try! is fine.
    try! stream.sendMessage(response)
  }

  /// Returns true if there are response streams enqueued for 'GetChannelCredential'
  internal var hasGetChannelCredentialResponsesRemaining: Bool {
    return self.fakeChannel.hasFakeResponseEnqueued(forPath: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/GetChannelCredential")
  }

  /// Make a unary response for the SetChannelCredential RPC. This must be called
  /// before calling 'setChannelCredential'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  internal func makeSetChannelCredentialResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest, Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialResponse> {
    return self.fakeChannel.makeFakeUnaryResponse(path: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/SetChannelCredential", requestHandler: requestHandler)
  }

  internal func enqueueSetChannelCredentialResponse(
    _ response: Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialResponse,
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Adapter_V1beta_SetChannelCredentialRequest>) -> () = { _ in }
  )  {
    let stream = self.makeSetChannelCredentialResponseStream(requestHandler)
    // This is the only operation on the stream; try! is fine.
    try! stream.sendMessage(response)
  }

  /// Returns true if there are response streams enqueued for 'SetChannelCredential'
  internal var hasSetChannelCredentialResponsesRemaining: Bool {
    return self.fakeChannel.hasFakeResponseEnqueued(forPath: "/sinch.conversationapi.adapter.v1beta.ChannelCredential/SetChannelCredential")
  }
}

