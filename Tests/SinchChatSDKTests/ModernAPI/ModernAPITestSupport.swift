import Foundation
import Combine

@testable import SinchChatSDK

/// Storage for values written from the SDK's completion handlers, which run on an arbitrary thread.
final class Locked<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

enum ModernAPIError: Error, Equatable {
    case boom
}

/// A `handleEvents(receiveCancel:)` handler that is callable from any thread.
///
/// A closure built inside a `@MainActor` test would inherit that isolation; this one is `@Sendable`, so the SDK may
/// invoke it wherever the subscription is cancelled.
func cancellationHandler(_ flag: Locked<Bool>) -> @Sendable () -> Void {
    { flag.value = true }
}

/// A config that never reaches the network: every modern API test stubs the push forwarder.
func modernAPIConfig() -> SinchSDKConfig.AppConfig {
    .init(clientID: "client-id", projectID: "project-id", configID: "config-id", region: .EU1)
}

/// Records the plugin events of the shared subject.
///
/// The sink is built outside any actor, so it can be called from whatever thread the SDK sends the event on. A sink
/// created inside a `@MainActor` test would inherit that isolation and trap when the SDK sends from another thread.
final class PluginEventRecorder: @unchecked Sendable {

    private let events = Locked<[SinchPluginEvent]>([])
    private let subscription: AnyCancellable

    init(subject: PassthroughSubject<SinchPluginEvent, Never>) {
        let events = self.events
        subscription = subject.sink { event in
            events.mutate { $0.append(event) }
        }
    }

    deinit {
        subscription.cancel()
    }

    var received: [SinchPluginEvent] {
        events.value
    }

    func count(of kind: Kind) -> Int {
        events.value.filter(kind.matches).count
    }

    enum Kind {
        case didRemoveIdentity

        func matches(_ event: SinchPluginEvent) -> Bool {
            switch (self, event) {
            case (.didRemoveIdentity, .didRemoveIdentity): return true
            default: return false
            }
        }
    }
}
