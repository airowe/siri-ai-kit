import Foundation
import Security

public enum KeychainAccessibility: Sendable {
    /// Readable once the phone has been unlocked after a restart, including while it's locked again. Siri needs this to run tools on a locked phone.
    case afterFirstUnlockThisDeviceOnly
    case afterFirstUnlock
    case whenUnlockedThisDeviceOnly
    case whenUnlocked

    var attribute: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        }
    }
}

public struct KeychainTokenStore: TokenStore {
    public let service: String
    public let account: String
    public let accessibility: KeychainAccessibility

    public init(
        service: String,
        account: String = "tokens",
        accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.account = account
        self.accessibility = accessibility
    }

    private var itemQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func load() throws(ToolError) -> Tokens? {
        var query = itemQuery
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw .keychain(status) }
        do {
            return try JSONDecoder().decode(Tokens.self, from: data)
        } catch {
            throw .invalidResponse
        }
    }

    public func save(_ tokens: Tokens) throws(ToolError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokens)
        } catch {
            throw .invalidResponse
        }
        SecItemDelete(itemQuery as CFDictionary)
        let status = SecItemAdd(addAttributes(for: data) as CFDictionary, nil)
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func addAttributes(for data: Data) -> [CFString: Any] {
        var item = itemQuery
        item[kSecValueData] = data
        item[kSecAttrAccessible] = accessibility.attribute
        return item
    }

    public func clear() {
        SecItemDelete(itemQuery as CFDictionary)
    }
}
