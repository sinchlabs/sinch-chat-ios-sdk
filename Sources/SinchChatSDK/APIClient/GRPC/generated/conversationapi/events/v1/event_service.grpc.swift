//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: sinch/conversationapi/events/v1/event_service.proto
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


/// The Event API
///
/// Usage: instantiate `Sinch_Conversationapi_Events_V1_EventsClient`, then call methods of this protocol to make API calls.
internal protocol Sinch_Conversationapi_Events_V1_EventsClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol? { get }

  func sendEvent(
    _ request: Sinch_Conversationapi_Events_V1_SendEventRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Sinch_Conversationapi_Events_V1_SendEventRequest, Sinch_Conversationapi_Events_V1_SendEventResponse>
}

extension Sinch_Conversationapi_Events_V1_EventsClientProtocol {
  internal var serviceName: String {
    return "sinch.conversationapi.events.v1.Events"
  }

  /// Send an event
  ///
  /// Sends an event to the referenced contact from the referenced app.
  /// Note that this operation enqueues the event in a queues so a successful
  /// response only indicates that the event has been queued. 
  ///
  /// - Parameters:
  ///   - request: Request to send to SendEvent.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func sendEvent(
    _ request: Sinch_Conversationapi_Events_V1_SendEventRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Sinch_Conversationapi_Events_V1_SendEventRequest, Sinch_Conversationapi_Events_V1_SendEventResponse> {
    return self.makeUnaryCall(
      path: "/sinch.conversationapi.events.v1.Events/SendEvent",
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSendEventInterceptors() ?? []
    )
  }
}

internal protocol Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol {

  /// - Returns: Interceptors to use when invoking 'sendEvent'.
  func makeSendEventInterceptors() -> [ClientInterceptor<Sinch_Conversationapi_Events_V1_SendEventRequest, Sinch_Conversationapi_Events_V1_SendEventResponse>]
}

internal final class Sinch_Conversationapi_Events_V1_EventsClient: Sinch_Conversationapi_Events_V1_EventsClientProtocol {
  internal let channel: GRPCChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol?

  /// Creates a client for the sinch.conversationapi.events.v1.Events service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

internal final class Sinch_Conversationapi_Events_V1_EventsTestClient: Sinch_Conversationapi_Events_V1_EventsClientProtocol {
  private let fakeChannel: FakeChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol?

  internal var channel: GRPCChannel {
    return self.fakeChannel
  }

  internal init(
    fakeChannel: FakeChannel = FakeChannel(),
    defaultCallOptions callOptions: CallOptions = CallOptions(),
    interceptors: Sinch_Conversationapi_Events_V1_EventsClientInterceptorFactoryProtocol? = nil
  ) {
    self.fakeChannel = fakeChannel
    self.defaultCallOptions = callOptions
    self.interceptors = interceptors
  }

  /// Make a unary response for the SendEvent RPC. This must be called
  /// before calling 'sendEvent'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  internal func makeSendEventResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Events_V1_SendEventRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Sinch_Conversationapi_Events_V1_SendEventRequest, Sinch_Conversationapi_Events_V1_SendEventResponse> {
    return self.fakeChannel.makeFakeUnaryResponse(path: "/sinch.conversationapi.events.v1.Events/SendEvent", requestHandler: requestHandler)
  }

  internal func enqueueSendEventResponse(
    _ response: Sinch_Conversationapi_Events_V1_SendEventResponse,
    _ requestHandler: @escaping (FakeRequestPart<Sinch_Conversationapi_Events_V1_SendEventRequest>) -> () = { _ in }
  )  {
    let stream = self.makeSendEventResponseStream(requestHandler)
    // This is the only operation on the stream; try! is fine.
    try! stream.sendMessage(response)
  }

  /// Returns true if there are response streams enqueued for 'SendEvent'
  internal var hasSendEventResponsesRemaining: Bool {
    return self.fakeChannel.hasFakeResponseEnqueued(forPath: "/sinch.conversationapi.events.v1.Events/SendEvent")
  }
}

