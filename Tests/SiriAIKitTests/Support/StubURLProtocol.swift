import Foundation

/// Answers requests from a per-session handler, so tests can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var logs: [String: [URLRequest]] = [:]
    private static let idHeader = "X-Stub-ID"

    struct Stub: Sendable {
        let id: String
        let session: URLSession

        var requests: [URLRequest] { StubURLProtocol.lock.withLock { StubURLProtocol.logs[id] ?? [] } }

        func respond(_ handler: @escaping Handler) {
            StubURLProtocol.lock.withLock { StubURLProtocol.handlers[id] = handler }
        }
    }

    static func makeStub() -> Stub {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let id = UUID().uuidString
        configuration.httpAdditionalHeaders = [idHeader: id]
        return Stub(id: id, session: URLSession(configuration: configuration))
    }

    static func reply(_ status: Int, _ body: String = "", for request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let id = request.value(forHTTPHeaderField: Self.idHeader) ?? ""
        let handler = Self.lock.withLock { () -> Handler? in
            Self.logs[id, default: []].append(request.withBody(from: request))
            return Self.handlers[id]
        }
        DispatchQueue.global().async { [self] in
            do {
                guard let handler else { throw URLError(.cannotConnectToHost) }
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession moves bodies into a stream before protocols see them; read it back for assertions.
    func withBody(from original: URLRequest) -> URLRequest {
        guard httpBody == nil, let stream = httpBodyStream else { return self }
        var copy = self
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        copy.httpBody = data
        return copy
    }
}
