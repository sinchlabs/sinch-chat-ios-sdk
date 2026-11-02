//  The per-install id, pinned through an injected backing so the tests do not write
//  to the login Keychain. One round-trip test uses the real Keychain under a private
//  service and skips only on `errSecMissingEntitlement` (-34018).

import Security
import XCTest

@testable import SinchPushSDK

final class InstallationIdTests: XCTestCase {

    private static let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

    private final class CountingGenerator: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func next() -> String {
            lock.lock()
            count += 1
            lock.unlock()
            return KeychainInstallationIdStore.newIdentifier()
        }
    }

    /// A backing with a slot that cannot be read or refuses writes.
    private final class FallibleInstallationIdBacking: InstallationIdBacking, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        private var isReadable: Bool
        private var isWritable: Bool
        private var saves = 0

        init(id: String? = nil, readable: Bool = true, writable: Bool = true) {
            self.stored = id
            self.isReadable = readable
            self.isWritable = writable
        }

        var saveCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return saves
        }

        var storedId: String? {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func setReadable(_ readable: Bool) {
            lock.lock()
            defer { lock.unlock() }
            isReadable = readable
        }

        func setWritable(_ writable: Bool) {
            lock.lock()
            defer { lock.unlock() }
            isWritable = writable
        }

        func loadInstallationId() -> InstallationIdLoad {
            lock.lock()
            defer { lock.unlock() }
            guard isReadable else {
                return .unavailable(reason: "the keychain returned status -25308")
            }
            guard let stored else { return .absent }
            return .found(stored)
        }

        func saveInstallationId(_ id: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            saves += 1
            guard isWritable else { return false }
            stored = id
            return true
        }
    }

    private func isCanonicalUUID(_ value: String) -> Bool {
        value.range(of: Self.uuidPattern, options: .regularExpression) != nil
    }

    // MARK: - Format

    func testTheGeneratedIdIsALowercaseCanonicalUUID() throws {
        let store = KeychainInstallationIdStore(
            backing: InMemoryInstallationIdBacking(), logger: SilentSocketLogger())

        let id = try store.installationId()

        XCTAssertTrue(
            isCanonicalUUID(id),
            "\(id) is not a lowercase canonical UUID (8-4-4-4-12)")
        XCTAssertEqual(id, id.lowercased())
    }

    func testAPreExistingIdIsReturnedUnchanged() throws {
        let persisted = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        let generator = CountingGenerator()
        let store = KeychainInstallationIdStore(
            backing: InMemoryInstallationIdBacking(id: persisted),
            generate: generator.next,
            logger: SilentSocketLogger())

        XCTAssertEqual(try store.installationId(), persisted)
        XCTAssertEqual(try store.installationId(), persisted)
        XCTAssertEqual(generator.callCount, 0, "a persisted id was regenerated")
    }

    func testAnEmptyStoredValueCountsAsNoValue() throws {
        let generator = CountingGenerator()
        let store = KeychainInstallationIdStore(
            backing: InMemoryInstallationIdBacking(id: ""),
            generate: generator.next,
            logger: SilentSocketLogger())

        XCTAssertTrue(isCanonicalUUID(try store.installationId()))
        XCTAssertEqual(generator.callCount, 1)
    }

    func testAPersistedValueThatIsNotAUuidIsReplaced() throws {
        for garbage in ["not-a-uuid", "3f2504e04f8941d39a0c0305e82c3301", "3f2504e0-4f89-41d3-9a0c"] {
            let generator = CountingGenerator()
            let backing = InMemoryInstallationIdBacking(id: garbage)
            let store = KeychainInstallationIdStore(
                backing: backing, generate: generator.next, logger: SilentSocketLogger())

            let id = try store.installationId()

            XCTAssertTrue(isCanonicalUUID(id), "\(garbage) was used as an installation id")
            XCTAssertEqual(generator.callCount, 1)
            XCTAssertEqual(backing.storedId, id, "the old value was not overwritten")
        }
    }

    func testAPersistedIdInAnotherCaseIsNormalisedAndKept() throws {
        let persisted = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        let generator = CountingGenerator()
        let store = KeychainInstallationIdStore(
            backing: InMemoryInstallationIdBacking(id: persisted),
            generate: generator.next,
            logger: SilentSocketLogger())

        let id = try store.installationId()

        XCTAssertEqual(id, persisted.lowercased())
        XCTAssertTrue(isCanonicalUUID(id))
        XCTAssertEqual(generator.callCount, 0, "an uppercase id was thrown away")
        XCTAssertEqual(try store.installationId(), id)
    }

    // MARK: - Generated once, stable

    func testTheIdIsGeneratedOnceAndThenReused() throws {
        let generator = CountingGenerator()
        let backing = InMemoryInstallationIdBacking()
        let store = KeychainInstallationIdStore(
            backing: backing, generate: generator.next, logger: SilentSocketLogger())

        let first = try store.installationId()
        let second = try store.installationId()

        XCTAssertEqual(first, second)
        XCTAssertEqual(generator.callCount, 1)
        XCTAssertEqual(backing.storedId, first)
    }

    func testTheIdIsStableAcrossStoreInstancesOverTheSameBacking() throws {
        // A relaunch: a brand-new store over the storage the previous process left behind.
        let backing = InMemoryInstallationIdBacking()
        let before = KeychainInstallationIdStore(backing: backing, logger: SilentSocketLogger())
        let id = try before.installationId()

        let after = KeychainInstallationIdStore(backing: backing, logger: SilentSocketLogger())
        XCTAssertEqual(try after.installationId(), id)

        let third = KeychainInstallationIdStore(backing: backing, logger: SilentSocketLogger())
        XCTAssertEqual(try third.installationId(), id)
    }

    func testConcurrentFirstCallsReturnOneId() throws {
        let generator = CountingGenerator()
        let backing = InMemoryInstallationIdBacking()
        let store = KeychainInstallationIdStore(
            backing: backing, generate: generator.next, logger: SilentSocketLogger())

        // No barrier, so the threads genuinely overlap.
        let seenIds = Collector()
        let failures = Counter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            do {
                seenIds.append(try store.installationId())
            } catch {
                failures.increment()
            }
        }
        let seen = seenIds.values

        XCTAssertEqual(failures.value, 0, "a concurrent call failed on a working slot")
        XCTAssertEqual(Set(seen).count, 1, "concurrent first calls disagreed: \(Set(seen))")
        XCTAssertEqual(generator.callCount, 1, "an id was generated more than once")
        XCTAssertEqual(backing.storedId, seen.first)
    }

    // MARK: - An unreadable slot is not an empty one

    func testAnUnreadableSlotReportsFailureAndTouchesNothing() throws {
        // Before the first unlock the Keychain answers errSecInteractionNotAllowed: the id
        // exists but cannot be read, so minting a replacement would overwrite it.
        let persisted = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        let generator = CountingGenerator()
        let backing = FallibleInstallationIdBacking(id: persisted, readable: false)
        let store = KeychainInstallationIdStore(
            backing: backing, generate: generator.next, logger: SilentSocketLogger())

        XCTAssertThrowsError(try store.installationId()) { error in
            guard case InstallationIdError.unavailable = error else {
                return XCTFail("expected an unavailable failure, got \(error)")
            }
        }
        XCTAssertEqual(generator.callCount, 0, "an id was minted while the slot was unreadable")
        XCTAssertEqual(backing.saveCount, 0, "the slot was written while it was unreadable")
        XCTAssertEqual(backing.storedId, persisted)

        backing.setReadable(true)
        XCTAssertEqual(try store.installationId(), persisted)
        XCTAssertEqual(generator.callCount, 0, "the unreadable read was cached")
    }

    func testAnIdThatCouldNotBePersistedIsNotHandedOut() throws {
        let generator = CountingGenerator()
        let backing = FallibleInstallationIdBacking(readable: true, writable: false)
        let store = KeychainInstallationIdStore(
            backing: backing, generate: generator.next, logger: SilentSocketLogger())

        XCTAssertThrowsError(try store.installationId()) { error in
            guard case InstallationIdError.unavailable = error else {
                return XCTFail("expected an unavailable failure, got \(error)")
            }
        }
        XCTAssertEqual(generator.callCount, 1, "generation should have been attempted")
        XCTAssertNil(backing.storedId)

        backing.setWritable(true)
        let id = try store.installationId()

        XCTAssertTrue(isCanonicalUUID(id))
        XCTAssertEqual(backing.storedId, id)
        XCTAssertEqual(try store.installationId(), id)
        XCTAssertEqual(generator.callCount, 2, "the failed attempt was served from the cache")
    }

    // MARK: - The Keychain item

    func testTheKeychainItemIsTheOneTheRelayContractNames() {
        XCTAssertEqual(KeychainInstallationIdBacking.defaultService, "com.sinch.push")
        XCTAssertEqual(KeychainInstallationIdBacking.defaultAccount, "installation-id")
    }

    func testTheSharedStoreIsOneInstance() {
        XCTAssertTrue(KeychainInstallationIdStore.shared === KeychainInstallationIdStore.shared)
    }

    func testARealKeychainSlotRoundTripsAndIsLoadedBack() throws {
        // Uses the real Keychain under a private service; skips only on errSecMissingEntitlement.
        try skipIfKeychainUnavailable()
        let service = "com.sinch.chatsdk.tests.installation-id"
        let account = "test-\(UUID().uuidString)"
        let backing = KeychainInstallationIdBacking(
            service: service, account: account, logger: SilentSocketLogger())
        defer {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ] as CFDictionary)
        }

        guard case .absent = backing.loadInstallationId() else {
            return XCTFail("a fresh account should read as absent")
        }
        let id = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        XCTAssertTrue(backing.saveInstallationId(id))
        guard case .found(let loaded) = backing.loadInstallationId() else {
            return XCTFail("a saved id was not found")
        }
        XCTAssertEqual(loaded, id)

        let store = KeychainInstallationIdStore(backing: backing, logger: SilentSocketLogger())
        XCTAssertEqual(try store.installationId(), id)
    }

    // MARK: - Keychain status mapping

    func testClassifyMapsKeychainStatusesToLoadOutcomes() throws {
        let id = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

        guard case .found(let value) = KeychainInstallationIdBacking.classify(
            status: errSecSuccess, data: Data(id.utf8))
        else { return XCTFail("success + UTF-8 should be found") }
        XCTAssertEqual(value, id)

        // Occupied but not text: found-but-corrupt, so the store regenerates over it.
        guard case .found(let corrupt) = KeychainInstallationIdBacking.classify(
            status: errSecSuccess, data: Data([0xFF, 0xFE, 0xFD]))
        else { return XCTFail("success + non-UTF-8 should be found-but-corrupt") }
        XCTAssertFalse(KeychainInstallationIdStore.isCanonicalInstallationId(corrupt))
        let backing = InMemoryInstallationIdBacking(id: corrupt)
        let store = KeychainInstallationIdStore(backing: backing, logger: SilentSocketLogger())
        XCTAssertTrue(isCanonicalUUID(try store.installationId()))

        guard case .absent = KeychainInstallationIdBacking.classify(
            status: errSecItemNotFound, data: nil)
        else { return XCTFail("errSecItemNotFound should be absent") }

        // errSecInteractionNotAllowed (-25308): locked before first unlock.
        // -34018: errSecMissingEntitlement, e.g. an unsigned test host or app.
        for status in [errSecInteractionNotAllowed, -34018] {
            guard case .unavailable = KeychainInstallationIdBacking.classify(status: status, data: nil)
            else { return XCTFail("status \(status) should be unavailable") }
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ value: String) {
        lock.lock()
        items.append(value)
        lock.unlock()
    }
}
