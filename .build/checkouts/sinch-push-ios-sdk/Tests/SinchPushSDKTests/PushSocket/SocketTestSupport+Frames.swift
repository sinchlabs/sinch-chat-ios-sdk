import Foundation

@testable import SinchPushSDK

// MARK: - Server frames

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame.OneOf_Payload) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = payload
    return frame
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_HelloAck) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.helloAck(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_Message) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.message(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_Ack) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.ack(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_Ping) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.ping(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_Close) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.close(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_AuthChallenge) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.authChallenge(payload))
}

func makeServerFrame(_ payload: Sinch_Push_Delivery_V1beta1_Ws_Pong) -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    makeServerFrame(.pong(payload))
}

// MARK: - Client frames

func helloClientFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ClientFrame {
    var hello = Sinch_Push_Delivery_V1beta1_Ws_Hello()
    hello.authToken = "jwt.token.value"
    hello.projectID = "project-1"
    hello.appID = "app-1"
    hello.userID = "user-1"
    hello.platform = .ios
    hello.background = true
    hello.lastSeenMessageID = "msg-9"
    hello.sdkVersion = "rn-sinch-push/1.0.1"
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
    frame.payload = .hello(hello)
    return frame
}

func pollClientFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ClientFrame {
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
    frame.payload = .poll(Sinch_Push_Delivery_V1beta1_Ws_Poll())
    return frame
}

func deliveryReportClientFrame(reportedAt: Int64 = 1_770_000_000_000) -> Sinch_Push_Delivery_V1beta1_Ws_ClientFrame {
    var report = Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport()
    report.messageID = "msg-1"
    report.sinchMessageID = "sinch-msg-1"
    report.status = .delivered
    report.reportedAtUnixMillis = reportedAt
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
    frame.payload = .deliveryReport(report)
    return frame
}

// MARK: - Server payloads

func authChallengeServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var challenge = Sinch_Push_Delivery_V1beta1_Ws_AuthChallenge()
    challenge.nonce = "nonce-1"
    challenge.issuedAtUnixMillis = 1_770_000_000_000
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .authChallenge(challenge)
    return frame
}

func helloAckServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
    ack.connectionID = "conn-1"
    ack.messages = [
        pooledMessage(messageID: "msg-1", enqueuedAt: 1_770_000_000_000),
        pooledMessage(messageID: "msg-2", enqueuedAt: 1_770_000_001_000)
    ]
    ack.pollIntervalMs = 5000
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .helloAck(ack)
    return frame
}

func messageServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
    message.ackToken = "ack-1"
    message.message = pooledMessage(messageID: "msg-1")
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .message(message)
    return frame
}

func ackServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var ack = Sinch_Push_Delivery_V1beta1_Ws_Ack()
    ack.ackToken = "ack-1"
    ack.accepted = false
    ack.error = "expired"
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .ack(ack)
    return frame
}

func pingServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var ping = Sinch_Push_Delivery_V1beta1_Ws_Ping()
    ping.correlationID = "corr-1"
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .ping(ping)
    return frame
}

func pongServerFrame(correlationID: String = "corr-1") -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .pong(Wire.pongMessage(correlationID: correlationID))
    return frame
}

func closeServerFrame() -> Sinch_Push_Delivery_V1beta1_Ws_ServerFrame {
    var close = Sinch_Push_Delivery_V1beta1_Ws_Close()
    close.reason = .unauthorized
    close.detail = "bad jwt"
    var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
    frame.payload = .close(close)
    return frame
}

// MARK: - Pooled messages

func pooledMessage(messageID: String, enqueuedAt: Int64 = 1_770_000_000_000) -> Sinch_Push_Delivery_V1beta1_Ws_PooledMessage {
    var alert = Sinch_Push_V1beta1_Resources_Alert()
    alert.title = "Grüße 🎉"
    alert.message = "body ✓"
    alert.imageURL = "https://example.test/i.png"

    var notification = Sinch_Push_V1beta1_Resources_PushNotification()
    notification.trackingID = "track-\(messageID)"
    notification.alert = alert
    notification.metadata = ["campaign": "spring", "locale": "de-DE"]
    notification.importance = .high
    notification.trigger = "push"

    var pooled = Sinch_Push_Delivery_V1beta1_Ws_PooledMessage()
    pooled.messageID = messageID
    pooled.sinchMessageID = "sinch-\(messageID)"
    pooled.pushNotification = notification
    pooled.enqueuedAtUnixMillis = enqueuedAt
    return pooled
}

/// Every optional string is set and empty, which proto3 cannot tell from unset.
func blankPooledMessage(
    messageID: String,
    sinchMessageID: String? = nil,
    enqueuedAt: Int64 = 1_770_000_000_000
) -> Sinch_Push_Delivery_V1beta1_Ws_PooledMessage {
    var alert = Sinch_Push_V1beta1_Resources_Alert()
    alert.title = ""
    alert.message = ""
    alert.imageURL = ""

    var notification = Sinch_Push_V1beta1_Resources_PushNotification()
    notification.alert = alert
    notification.trigger = ""
    notification.metadata = [:]

    var pooled = Sinch_Push_Delivery_V1beta1_Ws_PooledMessage()
    pooled.messageID = messageID
    pooled.sinchMessageID = sinchMessageID ?? "sinch-\(messageID)"
    pooled.pushNotification = notification
    pooled.enqueuedAtUnixMillis = enqueuedAt
    return pooled
}
