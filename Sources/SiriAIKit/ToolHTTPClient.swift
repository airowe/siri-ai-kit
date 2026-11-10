import Foundation

/// Calls your API from inside a tool's `perform()`, with a short timeout and errors Siri can speak.
public struct ToolHTTPClient: Sendable {
    public let baseURL: URL
    public let timeout: Duration
    let session: URLSession
    let outcomes: ToolOutcomeLog

    public init(
        baseURL: URL,
        timeout: Duration = .seconds(10),
        session: URLSession = .shared,
        outcomes: ToolOutcomeLog = .standard
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
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
        let (data, status) = try await load(request)
        guard (200..<300).contains(status) else { throw .rejected(status: status) }
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw .invalidResponse
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

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
