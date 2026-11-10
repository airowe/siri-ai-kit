#if os(iOS) && canImport(SiriEvaluations) && canImport(XCTest)
import AppIntentsTesting
import Evaluations
import SiriAIEvalSummary
import SiriEvaluations
import Testing

public enum BeforeRun: Sendable {
    case none
    /// Wait after launch, for example for an access token to expire.
    case waitFor(Duration)
}

/// Runs each scenario through Siri against your app, recording what the app's tool did after every run.
@available(iOS 27.3, *)
public struct ToolEvaluation: Evaluation {
    public let name: String
    public let harness: SiriAppHarness
    public let before: BeforeRun
    public let dataset: SiriScenarioLoader

    public init(name: String, harness: SiriAppHarness, before: BeforeRun = .none, dataset: SiriScenarioLoader) {
        self.name = name
        self.harness = harness
        self.before = before
        self.dataset = dataset
    }

    public func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await harness.launchAndWaitUntilReady()
        if case .waitFor(let duration) = before {
            try await Task.sleep(for: duration)
        }
        let subject = try await SiriService.run(scenario: sample)
        let outcome = await harness.lastToolOutcome() ?? "tool outcome missing"
        print("[siri-ai-eval] outcome: \(outcome)")
        Attachment.record(outcome, named: "\(ExportReader.outcomeAttachmentPrefix).txt")
        return subject
    }

    public var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    public func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}
#endif
