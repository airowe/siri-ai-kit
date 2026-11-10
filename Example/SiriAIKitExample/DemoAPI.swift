import Foundation
import SiriAIKit

/// DummyJSON's public demo account, with one-minute access tokens so every test exercises expiry.
enum DemoAPI {
    static let base = URL(string: "https://dummyjson.com")!
    static let appName = "SiriAIKit Example"
    static let username = "emilys"
    static let password = "emilyspass"
    static let accessTokenLifetimeMinutes = 1
    /// Set to false for the negative control: every expired call must then reply "sign in again".
    static let refreshEnabled = true

    static let store = KeychainTokenStore(service: "com.example.siriaikit.auth")

    static let authenticator = TokenAuthenticator(store: store) { tokens in
        guard refreshEnabled else { throw ToolError.signedOut }
        return try await unauthenticated.send(
            .post, "auth/refresh",
            body: RefreshBody(refreshToken: tokens.refreshToken, expiresInMins: accessTokenLifetimeMinutes),
            as: Tokens.self
        )
    }

    static let client = ToolHTTPClient(baseURL: base, auth: authenticator)
    private static let unauthenticated = ToolHTTPClient(baseURL: base)

    static func signIn() async throws {
        let tokens = try await unauthenticated.send(
            .post, "auth/login",
            body: LoginBody(username: username, password: password, expiresInMins: accessTokenLifetimeMinutes),
            as: Tokens.self
        )
        try store.save(tokens)
    }

    static func signOut() { store.clear() }

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
