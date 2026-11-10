#if DEBUG
import Security
import Testing
@testable import SiriAIKit

struct KeychainLockCheckTests {
    static let service = "com.example.auth"
    /// Raw values of the deprecated kSecAttrAccessibleAlways constants, which still appear on old items.
    static let always = "dk"
    static let alwaysThisDeviceOnly = "dku"

    @Test(arguments: [
        (kSecAttrAccessibleAfterFirstUnlock as String, true),
        (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, true),
        (always, true),
        (alwaysThisDeviceOnly, true),
        (kSecAttrAccessibleWhenUnlocked as String, false),
        (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String, false),
        (kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String, false),
    ])
    func isReadableWhenLocked(accessible: String, expected: Bool) {
        #expect(KeychainLockCheck.isReadableWhenLocked(accessible) == expected)
    }

    @Test func missingItemIsSilent() {
        #expect(KeychainLockCheck.lockWarning(service: Self.service, status: errSecItemNotFound, accessible: nil) == nil)
    }

    @Test func readableItemIsSilent() {
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        #expect(KeychainLockCheck.lockWarning(service: Self.service, status: errSecSuccess, accessible: accessible) == nil)
    }

    @Test func whenUnlockedWarns() throws {
        let accessible = kSecAttrAccessibleWhenUnlocked as String
        let warning = try #require(KeychainLockCheck.lockWarning(service: Self.service, status: errSecSuccess, accessible: accessible))
        #expect(warning.contains(Self.service))
        #expect(warning.contains("can't read it while the phone is locked"))
    }

    @Test func otherStatusWarnsWithStatus() throws {
        let warning = try #require(KeychainLockCheck.lockWarning(service: Self.service, status: -34018, accessible: nil))
        #expect(warning.contains("status -34018"))
        #expect(warning.contains(Self.service))
    }
}
#endif
