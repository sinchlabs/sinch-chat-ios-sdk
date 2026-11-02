import Security
import XCTest

/// Skips the calling test when the host has no Keychain entitlement.
/// Only `errSecMissingEntitlement` (-34018) skips: any other failure is a real failure.
func skipIfKeychainUnavailable(file: StaticString = #filePath, line: UInt = #line) throws {
    let service = "com.sinch.chatsdk.tests.keychain-probe"
    let account = "probe"
    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: Data([0])
    ]
    let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    SecItemDelete(deleteQuery as CFDictionary)
    try XCTSkipIf(
        status == errSecMissingEntitlement,
        "Keychain unavailable in host-less test bundle (errSecMissingEntitlement)",
        file: file,
        line: line)
}
