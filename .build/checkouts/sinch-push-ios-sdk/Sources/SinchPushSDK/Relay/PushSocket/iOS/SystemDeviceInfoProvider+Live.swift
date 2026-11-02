import Foundation

extension SystemDeviceInfoProvider {
    // Uses the shared installation ID store for both Hello and Subscribe.
    static func live(
        installationIdStore: InstallationIdStore = KeychainInstallationIdStore.shared,
        logger: SocketLogger = PrintSocketLogger(),
        relaySwitch: RelaySwitchStore = InMemoryRelaySwitchStore()
    ) -> SystemDeviceInfoProvider {
        SystemDeviceInfoProvider(
            installationId: { try installationIdStore.installationId() },
            logger: logger,
            relaySwitch: relaySwitch
        )
    }
}
