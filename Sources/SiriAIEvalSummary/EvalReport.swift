/// One run of a Siri evaluation scenario.
public struct EvalRun: Sendable, Equatable, Codable {
    /// Intent name → whether Siri called it.
    public let toolCalls: [String: Bool]
    public let reply: String?
    public let intentsPassed: Bool
    public let replyPassed: Bool
    /// The harness scored the run before its results arrived; the tool may well have run.
    public let incomplete: Bool
    /// What the app's tool did in this run ("refreshed after 401 at …"), when the harness recorded it.
    public var outcome: String?

    public init(
        toolCalls: [String: Bool], reply: String?, intentsPassed: Bool, replyPassed: Bool, incomplete: Bool,
        outcome: String? = nil
    ) {
        self.toolCalls = toolCalls
        self.reply = reply
        self.intentsPassed = intentsPassed
        self.replyPassed = replyPassed
        self.incomplete = incomplete
        self.outcome = outcome
    }

    public var passed: Bool { intentsPassed && replyPassed }
}

public struct EvalReport: Sendable, Equatable, Codable {
    public let name: String
    public var runs: [EvalRun]
    /// Outcomes recorded during this evaluation that couldn't be matched one-to-one with its runs.
    public var unmatchedOutcomes: [String]

    public init(name: String, runs: [EvalRun], unmatchedOutcomes: [String] = []) {
        self.name = name
        self.runs = runs
        self.unmatchedOutcomes = unmatchedOutcomes
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
