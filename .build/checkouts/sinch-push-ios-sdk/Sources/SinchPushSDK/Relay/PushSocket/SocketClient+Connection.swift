import Foundation

extension SocketClient {

    func open() {
        // Read the persisted slices before the first attempt, so a client connected
        // directly still starts with the seen set and outbox it left behind.
        loadPersistedStateIfNeeded()
        guard !stopped, !suspended, let configuration else { return }
        // A stale `lastError` must not survive into a fresh attempt.
        publish(
            status: attempts == 0 ? .connecting : .reconnecting,
            lastError: .clear)
        cancelReconnect()
        guard let url = URL(string: configuration.url) else {
            handleDisconnect(reason: "invalid socket url \(configuration.url)")
            return
        }

        let socket = transportFactory.makeTransport()
        generation += 1
        let currentGeneration = generation
        // Transport callbacks run on the transport's thread and hop onto the scheduler.
        socket.onOpen = { [weak self] in
            guard let self else { return }
            self.scheduler.perform { self.handleOpen(generation: currentGeneration) }
        }
        socket.onBinary = { [weak self] data in
            guard let self else { return }
            self.scheduler.perform { self.handleBinary(generation: currentGeneration, data: data) }
        }
        socket.onClose = { [weak self] close in
            guard let self else { return }
            self.scheduler.perform {
                self.handleTransportClose(generation: currentGeneration, close: close)
            }
        }
        transport = socket
        socket.connect(to: url)
        log("connecting to \(configuration.url)")
    }

    func handleOpen(generation: Int) {
        guard !retired, generation == self.generation else { return }
        log("socket open, sending Hello")
        sendHello()
    }

    /// The first frame on an open socket. The device info is read on every `Hello`,
    /// not cached, so an installation id that was unavailable earlier is retried.
    func sendHello() {
        guard let configuration, let transport, transport.isOpen else { return }
        var hello = Sinch_Push_Delivery_V1beta1_Ws_Hello()
        hello.authToken = configuration.authToken
        hello.projectID = configuration.projectID
        hello.appID = configuration.appID
        hello.userID = configuration.userID
        let device = deviceInfo.current(sdkVersionOverride: configuration.sdkVersion)
        hello.platform = device.platform
        // Not configurable on this path, so it cannot become true by accident.
        hello.background = false
        hello.lastSeenMessageID = lastSeenMessageID
        hello.sdkVersion = device.sdkVersion
        hello.installationID = device.installationId
        hello.osVersion = device.osVersion
        hello.bundleID = device.bundleId
        hello.backgroundService = device.backgroundService

        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .hello(hello)
        send(frame)
    }

    func handleBinary(generation: Int, data: Data) {
        guard !retired, generation == self.generation else { return }
        let frame: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame
        do {
            frame = try FrameCodec.decodeServerFrame(data)
        } catch let error as FrameCodecError {
            switch error {
            case .unknownTag(_, let tag):
                // The peer is ahead of this build. Logged apart from malformed envelopes.
                log("ignoring server frame: unknown frame tag \(tag)", level: .warning)
            default:
                // A bad envelope. The socket stays up.
                log("dropping malformed server frame: \(error)", level: .error)
            }
            return
        } catch {
            log("frame decode failed: \(error)", level: .error)
            return
        }
        guard let payload = frame.payload else {
            log("ignoring server frame: no payload set", level: .warning)
            return
        }
        handle(payload)
    }

    func handle(_ payload: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame.OneOf_Payload) {
        switch payload {
        case .helloAck(let ack):
            handleHelloAck(ack)

        case .message(let message):
            noteSessionWork()
            if message.hasMessage {
                emitMessage(message.message, ackToken: message.ackToken)
            } else {
                // No message id on this frame, so a FAILED report cannot name it and is not sent.
                tracker.queueFailure(
                    messageId: "",
                    sinchMessageId: "",
                    detail: "message frame without a pooled message")
            }

        case .ack(let ack):
            let outcome = tracker.handle(ack)
            // Only `accepted` counts as session work. A rejection, even `rate_limited`, does not.
            if outcome == .accepted {
                noteSessionWork()
            }
            // A rejection may have set a deferral, which only its own timer retries.
            // Re-arm on every Ack, not just at `HelloAck`.
            armDeferralTimer()
            log(
                "ack accepted=\(ack.accepted) error=\(ack.error.isEmpty ? "<none>" : ack.error)")

        case .ping(let ping):
            var pong = Sinch_Push_Delivery_V1beta1_Ws_Pong()
            pong.correlationID = ping.correlationID
            var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
            frame.payload = .pong(pong)
            send(frame)

        case .close(let close):
            handleClose(reason: close.reason, detail: SocketMessageEvent.absentIfEmpty(close.detail))

        case .authChallenge:
            // Reserved for token refresh. Logged, and the connection is kept.
            log("auth challenge received; reserved, connection kept")

        case .pong:
            break
        }
    }

    /// Handshake phases, in order: arm the reset, resolve the poll interval, publish
    /// `connected`, deliver the handshake's pooled messages, then poll and flush.
    func handleHelloAck(_ ack: Sinch_Push_Delivery_V1beta1_Ws_HelloAck) {
        noteHelloAck()

        pollIntervalMs = resolvedPollIntervalMs(serverMs: Int(ack.pollIntervalMs))

        publish(
            status: .connected,
            connectionId: ack.connectionID,
            lastError: .clear)

        // A HelloAck pooled message has no `Message` wrapper, so its ack token is empty.
        for pooled in ack.messages {
            emitMessage(pooled, ackToken: "")
        }

        startPolling()
        sendPoll()
        flushReports(.all)
        armDeferralTimer()
    }

    /// Config, then server, then default, raised to the 1000 ms floor. Only the floored value is published.
    func resolvedPollIntervalMs(serverMs: Int) -> Int {
        let requested: Int
        if let configured = configuration?.pollIntervalMs, configured > 0 {
            requested = configured
        } else if serverMs > 0 {
            requested = serverMs
        } else {
            requested = SocketClient.defaultPollIntervalMs
        }
        return max(SocketClient.minPollIntervalMs, requested)
    }

    func startPolling() {
        cancelPoll()
        let interval = pollIntervalMs
        pollTask = scheduler.schedule(after: interval) { [weak self] in
            self?.sendPoll()
            // Only forwarding failures are retried on the poll tick. `rate_limited` entries
            // keep their own deferral timer.
            self?.flushReports(.forwardFailureRetryOnly)
            self?.startPolling()
        }
    }

    func sendPoll() {
        guard state.status == .connected else { return }
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .poll(Sinch_Push_Delivery_V1beta1_Ws_Poll())
        send(frame)
    }

    func send(_ frame: Sinch_Push_Delivery_V1beta1_Ws_ClientFrame) {
        guard let transport, transport.isOpen else { return }
        do {
            transport.send(try FrameCodec.encodeClientFrame(frame))
        } catch {
            log("send failed: \(error)", level: .error)
        }
    }

    func handleClose(
        reason: Sinch_Push_Delivery_V1beta1_Ws_CloseReason,
        detail: String?
    ) {
        switch reason {
        case .stale:
            // The credential is good; only a fresh Hello is needed. Reconnect at once, with the budget reset.
            handleStale(detail: detail)
            return

        case .unauthorized:
            // Terminal until a credential refresh restarts the client.
            log("closed by the relay: unauthorized (terminal)", level: .error)
            let stopReason = detail ?? SocketClient.serverClosedReason(reason)
            stopTerminally(status: .authRequired, lastError: stopReason)
            if !authRefreshAttempted {
                authRefreshAttempted = true
                callbacks.onAuthRequired?()
            }
            return

        case .bgResumed:
            // Another surface owns the session. Stop and do not fight it.
            log("closed by the relay: BG_RESUMED, another surface owns the session", level: .warning)
            stopTerminally(status: .replaced, lastError: detail)
            return

        default:
            // Retryable server pressure. POOL_FULL also sheds, forfeiting an unspent reset.
            handleDisconnect(
                reason: detail ?? SocketClient.serverClosedReason(reason),
                shed: reason == .poolFull)
        }
    }

    /// The fallback text for a `Close` frame without `detail`. It does not expose a proto enum name.
    static func serverClosedReason(_ reason: Sinch_Push_Delivery_V1beta1_Ws_CloseReason) -> String {
        "server closed (reason=\(reason.rawValue))"
    }

    func handleStale(detail: String?) {
        clearTimers()
        closeSocket()
        guard !stopped, !suspended else { return }
        log("session stale, reconnecting immediately\(detail.map { " (\($0))" } ?? "")", level: .warning)
        attempts = 0
        open()
    }

    func handleTransportClose(
        generation: Int,
        close: SocketTransportClose
    ) {
        guard !retired, generation == self.generation else { return }
        // A failure before the socket was established is retryable, not a terminal error.
        handleDisconnect(reason: "socket closed (code=\(close.code))")
    }

    /// The socket is gone. Unless `shed`, this is attempt N+1 from the base delay.
    func handleDisconnect(reason: String, shed: Bool = false) {
        clearTimers()
        closeSocket()
        tracker.connectionClosed()
        guard !stopped, !suspended else { return }

        if shed && helloAckResetArmed {
            // The completed handshake was refused, so its reset was never real. Restoring
            // the pre-handshake count lets repeated denials climb to the cap.
            helloAckResetArmed = false
            attempts = attemptsBeforeHelloAck
        }
        attempts += 1
        publish(status: .reconnecting, lastError: .set(reason))
        let delay = ReconnectBackoff.delayMs(attempts: attempts, using: random)
        // Always scheduled, never immediate, so a zero delay cannot produce a hot loop.
        cancelReconnect()
        reconnectTask = scheduler.schedule(after: delay) { [weak self] in
            self?.open()
        }
    }

    func stopTerminally(status: SocketStatus, lastError: String?) {
        stopped = true
        sessionEpoch += 1
        clearTimers()
        closeSocket()
        tracker.connectionClosed()
        publish(status: status, lastError: .set(lastError))
    }

    /// Cancels the poll and reconnect timers, so a stopped client cannot reopen a socket.
    func clearTimers() {
        cancelPoll()
        cancelReconnect()
        cancelDeferral()
    }

    func cancelPoll() {
        pollTask?.cancel()
        pollTask = nil
    }

    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func cancelDeferral() {
        deferralTask?.cancel()
        deferralTask = nil
    }

    /// Detaches the callbacks before closing, so a replaced socket's trailing `onClose` is dropped.
    func closeSocket() {
        guard let socket = transport else { return }
        transport = nil
        socket.onOpen = nil
        socket.onBinary = nil
        socket.onClose = nil
        socket.close(code: 1000, reason: nil)
    }
}
