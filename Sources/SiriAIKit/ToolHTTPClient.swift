import Foundation

/// Calls your API from inside a tool's `perform()`, with a short timeout and errors Siri can speak.
public struct ToolHTTPClient: Sendable {
    public let baseURL: URL
    public let timeout: Duration
    let session: URLSession
    let auth: TokenAuthenticator?
    let outcomes: ToolOutcomeLog

    /// With `auth`, each request carries a bearer token, refreshed once if the API says it expired.
    public init(
        baseURL: URL,
        timeout: Duration = .seconds(10),
        session: URLSession = .shared,
        auth: TokenAuthenticator? = nil,
        outcomes: ToolOutcomeLog = .standard
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
        self.auth = auth
        self.outcomes = outcomes
    }

    public func get<R: Decodable>(_ path: String, as: R.Type) async throws(ToolError) -> R {
        try await perform(makeRequest(.get, path), as: R.self)
    }

    public func send<B: Encodable, R: Decodable>(
        _ method: HTTPMethod, _ path: String, body: B, as: R.Type
    ) async throws(ToolError) -> R {
        var request = makeRequest(method, path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw .invalidResponse
        }
        return try await perform(request, as: R.self)
    }

    func makeRequest(_ method: HTTPMethod, _ path: String) -> URLRequest {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var request = URLRequest(url: baseURL.appending(path: relative))
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout.seconds
        return request
    }

    func perform<R: Decodable>(_ request: URLRequest, as: R.Type) async throws(ToolError) -> R {
        let (data, status) = if let auth {
            try await loadAuthorized(request, auth: auth)
        } else {
            try await load(request)
        }
        guard (200..<300).contains(status) else { throw .rejected(status: status) }
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw .invalidResponse
        }
    }

    func loadAuthorized(_ request: URLRequest, auth: TokenAuthenticator) async throws(ToolError) -> (Data, Int) {
        do throws(ToolError) {
            let saved = try await auth.currentTokens()
            let first = try await load(request.authorized(with: saved))
            guard auth.expiredStatuses.contains(first.1) else {
                outcomes.record("used saved token")
                return first
            }
            let fresh = try await auth.refreshed(after: saved)
            let retry = try await load(request.authorized(with: fresh))
            guard !auth.expiredStatuses.contains(retry.1) else { throw .signedOut }
            outcomes.record("refreshed after \(first.1)")
            return retry
        } catch .signedOut {
            outcomes.record("signed out")
            throw .signedOut
        } catch .keychain(let status) {
            outcomes.record("signed out (keychain \(status))")
            throw .signedOut
        }
    }

    func load(_ request: URLRequest) async throws(ToolError) -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ToolError.invalidResponse }
            return (data, http.statusCode)
        } catch let error as ToolError {
            throw error
        } catch is CancellationError {
            throw .timedOut
        } catch let error as URLError {
            switch error.code {
            case .timedOut, .cancelled: throw .timedOut
            default: throw .unreachable
            }
        } catch {
            throw .unreachable
        }
    }
}

extension URLRequest {
    func authorized(with tokens: Tokens) -> URLRequest {
        var copy = self
        copy.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        return copy
    }
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
