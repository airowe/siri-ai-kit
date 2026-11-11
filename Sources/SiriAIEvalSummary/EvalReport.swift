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

    /// A complete run whose reply was right although an expected tool wasn't called: Siri most likely
    /// answered from what the app indexed in Spotlight, so the tool's code never ran.
    public var answeredWithoutTool: Bool {
        !incomplete && replyPassed && !intentsPassed && toolCalls.values.contains(false)
    }
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

    public var kind: EvaluationKind { EvaluationKind(evaluationName: name) }

    public var completeRunCount: Int { runs.count { !$0.incomplete } }

    public var answeredWithoutToolCount: Int { runs.count(where: \.answeredWithoutTool) }

    /// Complete runs whose reply check failed: in a negative control, every complete run should be one.
    public var replyFailedCompleteCount: Int { runs.count { !$0.incomplete && !$0.replyPassed } }
}

extension EvalReport {
    enum CodingKeys: String, CodingKey {
        case name, kind, runs, unmatchedOutcomes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            runs: try container.decode([EvalRun].self, forKey: .runs),
            unmatchedOutcomes: try container.decode([String].self, forKey: .unmatchedOutcomes)
        )
    }

    /// Writes `kind` too, derived from the name, so JSON readers needn't parse the tag.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(runs, forKey: .runs)
        try container.encode(unmatchedOutcomes, forKey: .unmatchedOutcomes)
    }
}

public enum EvalSummaryError: Error, Equatable {
    case malformed(file: String)
    case noEvaluations(path: String)
}
