# Refreshing tokens inside a Siri tool

Siri can call the tool after the access token expires, while the phone is locked, and again before an earlier call has finished. The refresh path has to survive all three.

Rules:

1. Refresh at most once per call. Never loop.
2. Save the new tokens before using them.
3. Run one refresh at a time for the whole app. A call that timed out may still be refreshing when the next starts, and APIs that rotate the refresh token reject the second use of the old one.
4. Only a rejected refresh (400, 401 or 403) means signed out. A server error, a network failure or a Keychain read error is not.
5. Save with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and update in place so a failed write never deletes the old tokens.

Pattern (adapt names to the app):

```swift
func orders() async throws -> [Order] {
    guard let tokens = try TokenKeychain.load() else { throw APIError.signedOut }
    let (data, status) = try await get("orders", token: tokens.accessToken)
    guard status == 401 else { return try decode(data, status: status) }

    let fresh = try await refresher.refreshed(after: tokens)
    ToolOutcomeLog.standard.note("refreshed after 401")
    let (retry, retryStatus) = try await get("orders", token: fresh.accessToken)
    guard retryStatus != 401 else { throw APIError.signedOut }
    return try decode(retry, status: retryStatus)
}

private actor Refresher {
    private var inFlight: Task<Tokens, any Error>?

    func refreshed(after stale: Tokens) async throws -> Tokens {
        if let inFlight { return try await inFlight.value }
        // Another call already refreshed: use its tokens instead of spending the old refresh token again.
        if let current = try TokenKeychain.load(), current.refreshToken != stale.refreshToken { return current }
        let task = Task { try await refresh(stale) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

private func refresh(_ tokens: Tokens) async throws -> Tokens {
    let fresh: Tokens
    do {
        fresh = try await post("auth/refresh", RefreshBody(refreshToken: tokens.refreshToken))
    } catch APIError.badStatus(let status) where [400, 401, 403].contains(status) {
        throw APIError.signedOut
    }
    try TokenKeychain.save(fresh)
    return fresh
}
```

The full working version, against a real API with one-minute tokens, is `Example/SiriAIKitExample/DemoAPI.swift` in the SiriAIKit repository.
