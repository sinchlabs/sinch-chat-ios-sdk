import Foundation

extension SocketClient {

    func flushIfConnected(_ mode: OutboxFlushMode) {
        guard state.status == .connected else { return }
        flushReports(mode)
    }

    func flushReports(_ mode: OutboxFlushMode) {
        guard state.status == .connected, let transport, transport.isOpen else { return }
        let now = scheduler.nowMs()
        let reports = tracker.reportsToSend(nowMs: now, mode: mode)
        guard !reports.isEmpty else { return }
        tracker.markSent(reports)
        for report in reports {
            var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
            frame.payload = .deliveryReport(report.deliveryReport(reportedAtMs: now))
            send(frame)
        }
    }

    /// Arms a one-shot retry for the next `rate_limited` deferral. Due deferrals
    /// retry at zero delay. Nothing is armed while the socket is closed; the
    /// HelloAck flush covers that case.
    func armDeferralTimer() {
        cancelDeferral()
        guard state.status == .connected, let transport, transport.isOpen else { return }
        let now = scheduler.nowMs()
        guard let deadline = tracker.nextDeferral() else { return }
        let delay = Int(max(0, deadline - now))
        deferralTask = scheduler.schedule(after: delay) { [weak self] in
            self?.flushReports(.deferredOnly)
            self?.armDeferralTimer()
        }
    }
}
