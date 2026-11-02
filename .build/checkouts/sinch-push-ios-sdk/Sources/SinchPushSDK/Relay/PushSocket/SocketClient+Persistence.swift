import Foundation

extension SocketClient {

    func loadPersistedStateIfNeeded() {
        guard !didLoadPersistedState else { return }
        didLoadPersistedState = true
        lastSeenMessageID = store.loadLastSeenMessageID()
        lastSeenEnqueuedAtMs = store.loadLastSeenEnqueuedAtMs()
        pendingMessages = store.loadPendingMessages()
        if configuration == nil, let persisted = store.loadConfiguration(),
            let token = tokenStore.loadToken() {
            configuration = persisted.configuration(authToken: token)
        }
    }

    /// Persists the configuration and the credential, each through its own store.
    func persistConfiguration() {
        guard let configuration else { return }
        store.saveConfiguration(configuration.persistable)
        tokenStore.saveToken(configuration.authToken)
    }
}
