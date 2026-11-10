/// One run of a Siri evaluation scenario.
public struct EvalRun: Sendable, Equatable, Codable {
    /// Intent name → whether Siri called it.
    public let toolCalls: [String: Bool]
    public let reply: String?
    public let intentsPassed: Bool
    public let replyPassed: Bool
    /// The harness scored the run before its results arrived; the tool may well have run.
    public let incomplete: Bool

    public init(toolCalls: [String: Bool], reply: String?, intentsPassed: Bool, replyPassed: Bool, incomplete: Bool) {
        self.toolCalls = toolCalls
        self.reply = reply
        self.intentsPassed = intentsPassed
        self.replyPassed = replyPassed
        self.incomplete = incomplete
    }

    public var passed: Bool { intentsPassed && replyPassed }
}

public struct EvalReport: Sendable, Equatable, Codable {
    public let name: String
    public let runs: [EvalRun]

    public init(name: String, runs: [EvalRun]) {
        self.name = name
        self.runs = runs
    }

    /// Passing runs over all runs, as Xcode reports it.
    public var applePassRate: Double {
        runs.isEmpty ? 0 : Double(runs.count(where: \.passed)) / Double(runs.count)
    }

    /// Passing runs over complete runs; `nil` when no run completed.
    public var realPassRate: Double? {
        let complete = runs.filter { !$0.incomplete }
        return complete.isEmpty ? nil : Double(complete.count(where: \.passed)) / Double(complete.count)
    }

    public var completeRunCount: Int { runs.count { !$0.incomplete } }
}

public enum EvalSummaryError: Error, Equatable {
    case malformed(file: String)
    case noEvaluations(path: String)
}
