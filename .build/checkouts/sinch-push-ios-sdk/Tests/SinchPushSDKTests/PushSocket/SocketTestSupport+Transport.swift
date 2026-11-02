import Foundation

@testable import SinchPushSDK

/// One fake socket, and the only way a test can drive the inbound side.
final class FakeSocketTransport: SocketTransport, @unchecked Sendable {
    private(set) var connectCalls: [URL] = []
    private(set) var sent: [Data] = []
    private(set) var closeCalls: [(code: Int, reason: String?)] = []

    var isOpen = false

    var onOpen: (@Sendable () -> Void)?

    var onBinary: (@Sendable (Data) -> Void)? {
        get { installedBinary }
        set {
            installedBinary = newValue
            if newValue != nil { retainedBinary = newValue }
        }
    }

    private var installedBinary: (@Sendable (Data) -> Void)?

    var onClose: (@Sendable (SocketTransportClose) -> Void)? {
        get { installedClose }
        set {
            installedClose = newValue
            if newValue != nil { retainedClose = newValue }
        }
    }

    private var installedClose: (@Sendable (SocketTransportClose) -> Void)?

    /// The handlers the client installed, kept after it clears them so a test can
    /// replay a replaced socket that keeps talking.
    fileprivate var retainedClose: (@Sendable (SocketTransportClose) -> Void)?
    fileprivate var retainedBinary: (@Sendable (Data) -> Void)?

    init() {}

    // MARK: - SocketTransport

    func connect(to url: URL) {
        connectCalls.append(url)
    }

    func send(_ data: Data) {
        guard isOpen else { return }
        sent.append(data)
    }

    func close(code: Int, reason: String?) {
        closeCalls.append((code: code, reason: reason))
        isOpen = false
    }

    // MARK: - Inbound drivers

    func openSocket() {
        isOpen = true
        onOpen?()
    }

    func deliver(_ frame: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame) {
        onBinary?(try! FrameCodec.encodeServerFrame(frame))
    }

    func deliverRaw(_ bytes: [UInt8]) {
        onBinary?(Data(bytes))
    }

    /// Closes the protocol session, then the socket; the client must have cleared its
    /// handlers by the trailing transport close.
    func serverClose(reason: Sinch_Push_Delivery_V1beta1_Ws_CloseReason, detail: String = "") {
        var close = Sinch_Push_Delivery_V1beta1_Ws_Close()
        close.reason = reason
        close.detail = detail
        deliver(makeServerFrame(close))
        failTransport(code: 1006)
    }

    func failTransport(code: Int, reason: String? = nil) {
        isOpen = false
        onClose?(SocketTransportClose(code: code, reason: reason))
    }

    func replayRetainedClose(code: Int = 1006) {
        retainedClose?(SocketTransportClose(code: code, reason: nil))
    }

    func replayRetainedBinary(_ frame: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame) {
        retainedBinary?(try! FrameCodec.encodeServerFrame(frame))
    }

    // MARK: - Outbound inspection

    /// Forced decode: a frame the codec rejects is a client bug, and the accessors
    /// below are non-throwing.
    var sentFrames: [Sinch_Push_Delivery_V1beta1_Ws_ClientFrame] {
        sent.map { try! FrameCodec.decodeClientFrame($0) }
    }

    var hellos: [Sinch_Push_Delivery_V1beta1_Ws_Hello] {
        sentFrames.compactMap {
            guard case .hello(let hello) = $0.payload else { return nil }
            return hello
        }
    }

    var hello: Sinch_Push_Delivery_V1beta1_Ws_Hello? { hellos.first }

    var polls: [Sinch_Push_Delivery_V1beta1_Ws_Poll] {
        sentFrames.compactMap {
            guard case .poll(let poll) = $0.payload else { return nil }
            return poll
        }
    }

    var reports: [Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport] {
        sentFrames.compactMap {
            guard case .deliveryReport(let report) = $0.payload else { return nil }
            return report
        }
    }

    var pongs: [Sinch_Push_Delivery_V1beta1_Ws_Pong] {
        sentFrames.compactMap {
            guard case .pong(let pong) = $0.payload else { return nil }
            return pong
        }
    }

    var sentKinds: [String] {
        sentFrames.map { frame in
            switch frame.payload {
            case .hello: return "hello"
            case .poll: return "poll"
            case .deliveryReport: return "report"
            case .pong: return "pong"
            case nil: return "none"
            }
        }
    }
}

/// Creates one fake socket per attempt and keeps them, replaced ones included.
final class FakeSocketTransportFactory: SocketTransportFactory, @unchecked Sendable {
    private(set) var sockets: [FakeSocketTransport] = []

    var createdCount: Int { sockets.count }

    var current: FakeSocketTransport? { sockets.last }

    func makeTransport() -> SocketTransport {
        let socket = FakeSocketTransport()
        sockets.append(socket)
        return socket
    }

    func reset() { sockets.removeAll() }
}
