import Foundation
@testable import SiriAIKit

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?
    private var _failSaves: OSStatus?
    private var _failLoads: OSStatus?
    private var _saveCount = 0

    init(_ tokens: Tokens? = nil) { self.tokens = tokens }

    var failSaves: OSStatus? {
        get { lock.withLock { _failSaves } }
        set { lock.withLock { _failSaves = newValue } }
    }

    var failLoads: OSStatus? {
        get { lock.withLock { _failLoads } }
        set { lock.withLock { _failLoads = newValue } }
    }

    var saveCount: Int { lock.withLock { _saveCount } }

    func load() throws(ToolError) -> Tokens? {
        lock.lock()
        defer { lock.unlock() }
        if let status = _failLoads { throw .keychain(status) }
        return tokens
    }

    func save(_ tokens: Tokens) throws(ToolError) {
        lock.lock()
        defer { lock.unlock() }
        if let status = _failSaves { throw .keychain(status) }
        self.tokens = tokens
        _saveCount += 1
    }

    func clear() { lock.withLock { tokens = nil } }
}
