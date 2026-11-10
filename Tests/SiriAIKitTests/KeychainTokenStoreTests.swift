import Foundation
import Security
import Testing
@testable import SiriAIKit

@Suite(.serialized)
struct KeychainTokenStoreTests {
    let service = "siri-ai-kit.tests.\(UUID().uuidString)"
    let first = Tokens(accessToken: "a1", refreshToken: "r1")
    let second = Tokens(accessToken: "a2", refreshToken: "r2")

    func makeStore(_ accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly) -> KeychainTokenStore {
        KeychainTokenStore(service: service, accessibility: accessibility)
    }

    @Test func savesAndLoadsTokens() throws {
        let store = makeStore()
        defer { store.clear() }
        try store.save(first)
        #expect(try store.load() == first)
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        #expect(try makeStore().load() == nil)
    }

    @Test func clearRemovesTokens() throws {
        let store = makeStore()
        try store.save(first)
        store.clear()
        #expect(try store.load() == nil)
    }

    @Test func saveReplacesExistingTokens() throws {
        let store = makeStore()
        defer { store.clear() }
        try store.save(first)
        try store.save(second)
        #expect(try store.load() == second)
    }

    /// Updating in place means the old tokens survive if writing the new ones fails, and readers never see a gap.
    @Test func saveUpdatesTheExistingItemInPlace() async throws {
        let store = makeStore()
        defer { store.clear() }
        try store.save(first)
        let created = try creationDate()
        try await Task.sleep(for: .milliseconds(1100))
        try store.save(second)
        #expect(try creationDate() == created)
        #expect(try store.load() == second)
    }

    func creationDate() throws -> Date {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "tokens",
            kSecReturnAttributes: true,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [CFString: Any])
        return try #require(attributes[kSecAttrCreationDate] as? Date)
    }

    @Test(arguments: [
        (KeychainAccessibility.afterFirstUnlockThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
        (.afterFirstUnlock, kSecAttrAccessibleAfterFirstUnlock as String),
        (.whenUnlockedThisDeviceOnly, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
        (.whenUnlocked, kSecAttrAccessibleWhenUnlocked as String),
    ])
    func appliesConfiguredAccessibility(accessibility: KeychainAccessibility, expected: String) {
        let attributes = makeStore(accessibility).addAttributes(for: Data("x".utf8))
        #expect(attributes[kSecAttrAccessible] as? String == expected)
        #expect(attributes[kSecAttrService] as? String == service)
        #expect(attributes[kSecAttrAccount] as? String == "tokens")
    }
}
