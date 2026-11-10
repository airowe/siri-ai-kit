#if DEBUG
import Foundation
import os
import Security

/// Warns, in debug builds, when a Keychain item your Siri tools read can't be read while the phone is locked.
///
/// Siri can run a tool on a locked phone. Items saved with `WhenUnlocked` protection, the default in some
/// secure-storage libraries, fail there even though they work whenever you test with the phone in your hand.
public enum KeychainLockCheck {
    /// Looks up the generic-password item and logs a warning once per service if Siri couldn't read it while locked.
    /// Silent when there's no item, so a signed-out app doesn't warn.
    public static func warnIfLockedOut(service: String, account: String? = nil) {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount] = account }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let accessible = (result as? [CFString: Any])?[kSecAttrAccessible] as? String
        guard let message = lockWarning(service: service, status: status, accessible: accessible),
              warned.insert(service)
        else { return }
        logger.warning("\(message, privacy: .public)")
    }

    /// Raw values of the deprecated `kSecAttrAccessibleAlways` constants, which old items can still carry.
    private static let readableWhenLocked: Set<String> = [
        kSecAttrAccessibleAfterFirstUnlock as String,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
        "dk",
        "dku",
    ]

    static func isReadableWhenLocked(_ accessible: String) -> Bool {
        readableWhenLocked.contains(accessible)
    }

    static func lockWarning(service: String, status: OSStatus, accessible: String?) -> String? {
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            return "SiriAIKit: couldn't read Keychain item \(service) (status \(status)); Siri tools may fail to read it too."
        }
        guard let accessible, !isReadableWhenLocked(accessible) else { return nil }
        return "SiriAIKit: Keychain item \(service) is \(accessible), so Siri tools can't read it while the phone is locked. "
            + "Save it with kSecAttrAccessibleAfterFirstUnlock or kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly."
    }

    private static let logger = Logger(subsystem: "SiriAIKit", category: "KeychainLockCheck")
    private static let warned = WarnedServices()
}

private final class WarnedServices: @unchecked Sendable {
    private let lock = NSLock()
    private var services: Set<String> = []

    func insert(_ service: String) -> Bool {
        lock.withLock { services.insert(service).inserted }
    }
}
#endif
