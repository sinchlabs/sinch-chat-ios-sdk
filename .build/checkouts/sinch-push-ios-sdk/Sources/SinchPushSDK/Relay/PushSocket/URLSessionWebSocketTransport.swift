import Foundation
import os

/// A `URLSessionWebSocketTask` behind the ``SocketTransport`` seam.
///
/// `@unchecked Sendable`: every field lives in one ``State`` behind `lock`. No
/// callback and no `URLSession` method runs while the lock is held.
final class URLSessionWebSocketTransport: SocketTransport, @unchecked Sendable {
    private struct State {
        var onOpen: (@Sendable () -> Void)?
        var onBinary: (@Sendable (Data) -> Void)?
        var onClose: (@Sendable (SocketTransportClose) -> Void)?

        var session: URLSession?
        var task: URLSessionWebSocketTask?
        var opened = false
        /// `URLSession` may report both an error and a close code. Only the first is reported.
        var closed = false
        /// Set by a local ``close(code:reason:)``, so its delegate callback is not reported as a peer close.
        var closingLocally = false
    }

    private let lock = OSAllocatedUnfairLock(uncheckedState: State())

    var onOpen: (@Sendable () -> Void)? {
        get { lock.withLock { $0.onOpen } }
        set { lock.withLock { $0.onOpen = newValue } }
    }

    var onBinary: (@Sendable (Data) -> Void)? {
        get { lock.withLock { $0.onBinary } }
        set { lock.withLock { $0.onBinary = newValue } }
    }

    var onClose: (@Sendable (SocketTransportClose) -> Void)? {
        get { lock.withLock { $0.onClose } }
        set { lock.withLock { $0.onClose = newValue } }
    }

    var isOpen: Bool { lock.withLock { $0.opened } }

    func connect(to url: URL) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        lock.withLock {
            $0.session = session
            $0.task = task
        }
        task.resume()
        // `URLSessionWebSocketTask` has no open callback, so the transport reports itself open after `resume()`.
        // A rejected upgrade surfaces through the receive closure.
        let onOpen = lock.withLock { state -> (@Sendable () -> Void)? in
            state.opened = true
            return state.onOpen
        }
        onOpen?()
        receiveNext()
    }

    func send(_ data: Data) {
        let task = lock.withLock { $0.opened ? $0.task : nil }
        guard let task else { return }
        task.send(.data(data)) { [weak self] error in
            guard let self, let error else { return }
            self.reportClose(code: 1006, reason: "send failed: \(error.localizedDescription)")
        }
    }

    func close(code: Int, reason: String?) {
        let task = lock.withLock { state -> URLSessionWebSocketTask? in
            guard let task = state.task else { return nil }
            state.closingLocally = true
            return task
        }
        guard let task else { return }
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task.cancel(with: closeCode, reason: reason?.data(using: .utf8))
        teardown(code: code, reason: reason)
    }

    private func receiveNext() {
        let task = lock.withLock { $0.task }
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.onBinary?(data)
                case .string:
                    // Text is not part of the protocol.
                    break
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure(let error):
                self.reportClose(code: 1006, reason: error.localizedDescription)
            }
        }
    }

    private func reportClose(code: Int, reason: String?) {
        let alreadyClosed = lock.withLock { state -> Bool in
            if state.closed { return true }
            state.closed = true
            return false
        }
        guard !alreadyClosed else { return }
        teardown(code: code, reason: reason)
    }

    private func teardown(code: Int, reason: String?) {
        // A local close is not reported, so one `stop()` cannot cause two reconnects.
        let (session, onClose) = lock.withLock { state -> (URLSession?, (@Sendable (SocketTransportClose) -> Void)?) in
            state.opened = false
            state.task = nil
            let session = state.session
            state.session = nil
            if state.closingLocally {
                state.closingLocally = false
                return (session, nil)
            }
            return (session, state.onClose)
        }
        session?.invalidateAndCancel()
        onClose?(SocketTransportClose(code: code, reason: reason))
    }
}

/// Hands out ``URLSessionWebSocketTransport`` instances, one per attempt.
final class URLSessionWebSocketTransportFactory: SocketTransportFactory {
    func makeTransport() -> SocketTransport {
        URLSessionWebSocketTransport()
    }
}
