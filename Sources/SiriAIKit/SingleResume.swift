import Foundation

/// A continuation that is resumed at most once, even if the result arrives before it's attached.
final class SingleResume<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var pending: Result<Value, any Error>?
    private var done = false

    func attach(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if let pending {
            done = true
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<Value, any Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        guard let continuation else {
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
