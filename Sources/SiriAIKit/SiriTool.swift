import Foundation

/// Runs your app's own API code inside a Siri tool: keeps to Siri's time budget,
/// turns failures into sentences Siri can say, and records what happened for evaluations.
public struct SiriTool: Sendable {
    public let appName: String
    public let timeout: Duration
    public let replies: ToolReplies
    let outcomes: ToolOutcomeLog
    let classify: @Sendable (any Error) -> ToolFailure?

    /// `classify` maps your own errors (for example "unauthorized") to a `ToolFailure`; return `nil` to use the defaults.
    public init(
        appName: String,
        timeout: Duration = .seconds(10),
        replies: ToolReplies = .default,
        outcomes: ToolOutcomeLog = .standard,
        classify: @escaping @Sendable (any Error) -> ToolFailure? = { _ in nil }
    ) {
        self.appName = appName
        self.timeout = timeout
        self.replies = replies
        self.outcomes = outcomes
        self.classify = classify
    }

    /// The operation's value, or a `ToolFailure` if it threw or ran past `timeout`.
    ///
    /// At the deadline, or if Siri cancels the call, this stops waiting but doesn't cancel the operation,
    /// so work like saving refreshed tokens still finishes.
    public func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws(ToolFailure) -> T {
        outcomes.beginRun()
        let task = Task { try await operation() }
        switch await Self.result(of: task, within: timeout) {
        case .success(let value):
            outcomes.record("succeeded")
            return value
        case .failure(let error):
            let failure = error is DeadlinePassed ? .timedOut : Self.classify(error, using: classify)
            outcomes.record(failure.outcome)
            throw failure
        }
    }

    /// The operation's answer, or the sentence Siri should say instead.
    public func answer(_ operation: @escaping @Sendable () async throws -> String) async -> String {
        do {
            return try await run(operation)
        } catch {
            return error.reply(appName: appName, overrides: replies)
        }
    }

    static func classify(_ error: any Error, using custom: (any Error) -> ToolFailure?) -> ToolFailure {
        if let mapped = custom(error) { return mapped }
        if let failure = error as? ToolFailure { return failure }
        if error is CancellationError { return .timedOut }
        if let urlError = error as? URLError {
            return [.timedOut, .cancelled].contains(urlError.code) ? .timedOut : .unreachable
        }
        return .failed
    }

    /// Waits for `task` without tying its lifetime to the caller: cancellation or the deadline end the wait only.
    private static func result<T: Sendable>(
        of task: Task<T, any Error>, within limit: Duration
    ) async -> Result<T, any Error> {
        let waiter = SingleResume<T>()
        let deadline = Task {
            try? await Task.sleep(for: limit)
            waiter.resume(with: .failure(DeadlinePassed()))
        }
        defer { deadline.cancel() }
        do {
            return .success(try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiter.attach(continuation)
                    Task { waiter.resume(with: await task.result) }
                }
            } onCancel: {
                waiter.resume(with: .failure(DeadlinePassed()))
            })
        } catch {
            return .failure(error)
        }
    }
}

private struct DeadlinePassed: Error {}

extension ToolFailure {
    var outcome: String {
        switch self {
        case .signedOut: "signed out"
        case .timedOut: "timed out"
        case .unreachable: "unreachable"
        case .failed: "failed"
        }
    }
}
