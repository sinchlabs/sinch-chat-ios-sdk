import Foundation
import SinchPushSDKNotificationExtension
import UIKit

@testable import SinchPushSDK

/// A reporter over fakes, with the passes it finishes observable.
final class DeliveryReporterRig: @unchecked Sendable {
    let scheduler = SerialManualScheduler()
    let store = FakeDeliveryReportStore()
    let outbox: DeliveryReportOutbox
    let sender = FakeDeliveryReportSender()
    let auth = ReportTestAuthDataSource()
    let center = NotificationCenter()
    let reporter: DeliveryReporter

    private let lock = NSLock()
    private var active = true
    private var extensionProcess = false
    private var activeReads = 0
    private var senders: [ObjectIdentifier: DeliveryReportSending] = [:]
    private var currentUploader: DeliveryReportUploading?
    private var sentMarkers: Set<ReportedDelivery> = []
    private var pendingFromExtension: [PendingDelivery] = []
    private var expired: Set<String> = []
    private var passIterator: AsyncStream<Void>.AsyncIterator
    private var finishedPasses = 0

    /// How many times the reporter asked whether the app is active.
    var applicationActiveReads: Int { lock.withLock { activeReads } }

    var isApplicationActive: Bool {
        get { lock.withLock { activeReads += 1; return active } }
        set { lock.withLock { active = newValue } }
    }

    var isNotificationServiceExtension: Bool {
        get { lock.withLock { extensionProcess } }
        set { lock.withLock { extensionProcess = newValue } }
    }

    /// The background uploader a wake in the background hands the deliveries to. `nil` means none.
    var uploader: DeliveryReportUploading? {
        get { lock.withLock { currentUploader } }
        set { lock.withLock { currentUploader = newValue } }
    }

    /// The deliveries a background upload has reported already.
    var sentDeliveries: Set<ReportedDelivery> {
        get { lock.withLock { sentMarkers } }
        set { lock.withLock { sentMarkers = newValue } }
    }

    /// The deliveries the notification service extension could not upload. The reporter takes them, once.
    var pendingDeliveries: [ReportedDelivery] {
        get { lock.withLock { pendingFromExtension.map { ReportedDelivery(messageID: $0.messageId, subscriberID: $0.subscriberId) } } }
        set { setPendingDeliveries(newValue, failedAgo: 0) }
    }

    /// Stores `deliveries` as the extension's, which failed `failedAgo` seconds ago on the scheduler's clock.
    func setPendingDeliveries(_ deliveries: [ReportedDelivery], failedAgo: TimeInterval) {
        let failedAt = Date(timeIntervalSince1970: Double(scheduler.nowMs()) / 1000 - failedAgo)
        lock.withLock {
            pendingFromExtension = deliveries.map {
                PendingDelivery(messageId: $0.messageID, subscriberId: $0.subscriberID, failedAt: failedAt)
            }
        }
    }

    /// The access tokens the reporter treats as expired.
    var expiredTokens: Set<String> {
        get { lock.withLock { expired } }
        set { lock.withLock { expired = newValue } }
    }

    init(random: Double = 0.5) {
        outbox = DeliveryReportOutbox(store: store)
        let (passes, passSink) = AsyncStream<Void>.makeStream()
        passIterator = passes.makeAsyncIterator()
        let holder = RigHolder()
        reporter = DeliveryReporter(
            outbox: outbox,
            dependencies: DeliveryReporter.Dependencies(
                scheduler: scheduler,
                random: ScriptedRandomSource(fixed: random),
                makeSender: { auth, _ in holder.rig?.sender(for: auth) ?? FakeDeliveryReportSender() },
                isApplicationActive: { holder.rig?.isApplicationActive ?? false },
                isNotificationServiceExtension: { holder.rig?.isNotificationServiceExtension ?? false },
                notificationCenter: center,
                uploader: { holder.rig?.uploader },
                sentDeliveries: { deliveries in
                    let sent = holder.rig?.sentDeliveries ?? []
                    return Set(deliveries.filter { sent.contains($0) })
                },
                pendingDeliveries: {
                    holder.rig?.lock.withLock {
                        defer { holder.rig?.pendingFromExtension = [] }
                        return holder.rig?.pendingFromExtension ?? []
                    } ?? []
                },
                isAccessTokenExpired: { token in holder.rig?.expiredTokens.contains(token) ?? false }))
        holder.rig = self
        reporter.onPassFinished = { [weak self] in
            self?.lock.withLock { self?.finishedPasses += 1 }
            passSink.yield()
        }
        reporter.setSession(authDataSource: auth, client: StubPushAPIClient())
    }

    /// Sends the session's batches through `sender` instead of the default one.
    func route(_ auth: ReportTestAuthDataSource, to sender: DeliveryReportSending) {
        lock.withLock { senders[ObjectIdentifier(auth)] = sender }
    }

    fileprivate func sender(for auth: AuthDataSource) -> DeliveryReportSending {
        lock.withLock { senders[ObjectIdentifier(auth)] } ?? sender
    }

    func queue(_ count: Int, subscriber: String = "s-1", prefix: String = "m") {
        for index in 0..<count {
            outbox.enqueue(messageID: "\(prefix)-\(index)", subscriberID: subscriber, enqueuedAtMs: scheduler.nowMs())
        }
    }

    /// Waits until `count` passes have ended in total.
    func waitForPasses(_ count: Int) async {
        while lock.withLock({ finishedPasses }) < count {
            _ = await passIterator.next()
        }
    }
}

private final class RigHolder: @unchecked Sendable {
    weak var rig: DeliveryReporterRig?
}

func rpcError(_ code: Int) -> Error {
    GrpcWebError.grpcStatus(code: code, message: "test")
}

/// Records the uploads it is handed, and starts them or not.
final class FakeDeliveryReportUploader: DeliveryReportUploading, @unchecked Sendable {
    struct Upload: Equatable {
        let deliveries: [ReportedDelivery]
        let accessToken: String
        let baseURL: URL
    }

    private let lock = NSLock()
    private var recorded: [Upload] = []

    /// Whether the uploads start.
    var starts = true

    var uploads: [Upload] { lock.withLock { recorded } }

    func upload(_ deliveries: [ReportedDelivery], accessToken: String, baseURL: URL) -> Bool {
        lock.withLock {
            guard starts else { return false }
            recorded.append(Upload(deliveries: deliveries, accessToken: accessToken, baseURL: baseURL))
            return true
        }
    }
}
