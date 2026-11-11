import Foundation
import Security
import SiriAIKit

/// The app's own API code. SiriAIKit doesn't manage auth; this file is the pattern for a Siri tool that reads a
/// saved token, refreshes it once on a 401, and saves tokens where a locked phone can still read them.
///
/// It uses DummyJSON's public demo account, with one-minute access tokens so every test exercises expiry.
enum DemoAPI {
    static let base = URL(string: "https://dummyjson.com")!
    static let appName = "SiriAIKit Example"
    static let keychainService = "com.example.siriaikit.auth"
    static let username = "emilys"
    static let password = "emilyspass"
    static let accessTokenLifetimeMinutes = 1
    /// Off only when an evaluation launches the app with `EvalSwitch.refreshOff`, for the negative control: every
    /// expired call must then reply "sign in again". Release builds ignore the switch.
    static var refreshEnabled: Bool {
        #if DEBUG
        !EvalSwitch.refreshOff.isOn()
        #else
        true
        #endif
    }

    static func signIn() async throws {
        let tokens: Tokens = try await post(
            "auth/login",
            LoginBody(username: username, password: password, expiresInMins: accessTokenLifetimeMinutes)
        )
        try TokenKeychain.save(tokens)
    }

    static func signOut() { TokenKeychain.clear() }

    /// The signed-in person's cart. Refreshes the access token once if the API says it expired, and never loops.
    static func cart() async throws -> Cart {
        guard let tokens = try TokenKeychain.load() else { throw DemoAPIError.signedOut }
        let (data, status) = try await get("auth/carts/1", token: tokens.accessToken)
        guard status == 401 else { return try decode(data, status: status) }

        let fresh = try await refresher.refreshed(after: tokens)
        ToolOutcomeLog.standard.note("refreshed after 401")
        let (retryData, retryStatus) = try await get("auth/carts/1", token: fresh.accessToken)
        guard retryStatus != 401 else { throw DemoAPIError.signedOut }
        return try decode(retryData, status: retryStatus)
    }

    /// One refresh at a time for the whole app. A Siri call that timed out may still be refreshing when the next
    /// one starts, and APIs that issue a new refresh token on every refresh reject the second use of the old one.
    private static let refresher = Refresher()

    private actor Refresher {
        private var inFlight: Task<Tokens, any Error>?

        func refreshed(after stale: Tokens) async throws -> Tokens {
            if let inFlight { return try await inFlight.value }
            if let current = try TokenKeychain.load(), current.refreshToken != stale.refreshToken {
                return current
            }
            let task = Task { try await DemoAPI.refresh(stale) }
            inFlight = task
            defer { inFlight = nil }
            return try await task.value
        }
    }

    /// New tokens, saved before they're used. Only a rejected refresh means signed out: a server error stays a
    /// failure and a network error stays "couldn't reach", so Siri doesn't ask the person to sign in for nothing.
    private static func refresh(_ tokens: Tokens) async throws -> Tokens {
        guard refreshEnabled else { throw DemoAPIError.signedOut }
        let fresh: Tokens
        do {
            fresh = try await post(
                "auth/refresh",
                RefreshBody(refreshToken: tokens.refreshToken, expiresInMins: accessTokenLifetimeMinutes)
            )
        } catch DemoAPIError.badStatus(let status) where [400, 401, 403].contains(status) {
            throw DemoAPIError.signedOut
        }
        try TokenKeychain.save(fresh)
        return fresh
    }

    private static func get(_ path: String, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: base.appending(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await load(request)
    }

    private static func post<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body) async throws -> Response {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, status) = try await load(request)
        return try decode(data, status: status)
    }

    private static func load(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func decode<Response: Decodable>(_ data: Data, status: Int) throws -> Response {
        guard (200..<300).contains(status) else { throw DemoAPIError.badStatus(status) }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct LoginBody: Encodable {
        let username: String
        let password: String
        let expiresInMins: Int
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String
        let expiresInMins: Int
    }
}

enum DemoAPIError: Error, Equatable {
    case signedOut
    case badStatus(Int)
    case keychain(OSStatus)
}

struct Tokens: Codable {
    let accessToken: String
    let refreshToken: String
}

/// Saves tokens readable after the first unlock, so Siri can use them while the phone is locked.
private enum TokenKeychain {
    static var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: DemoAPI.keychainService, kSecAttrAccount: "tokens"]
    }

    /// The saved tokens, or nil if there are none. Other Keychain failures throw, so a locked-phone read error
    /// isn't mistaken for being signed out.
    static func load() throws -> Tokens? {
        var lookup = query
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DemoAPIError.keychain(status) }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    /// Updates in place, so a failed write never deletes the tokens that were there.
    static func save(_ tokens: Tokens) throws {
        let changes: [CFString: Any] = [
            kSecValueData: try JSONEncoder().encode(tokens),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DemoAPIError.keychain(status) }
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
