#if os(iOS) && canImport(SiriEvaluations) && canImport(XCTest)
import AppIntentsTesting
import Evaluations
import SiriAIEvalSummary
import SiriAIKit
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
    /// The name you gave, tagged with `kind` unless it's `.required`, so `siri-ai-eval summarize` can tell kinds apart.
    public let name: String
    public let kind: EvaluationKind
    public let harness: SiriAppHarness
    public let before: BeforeRun
    public let dataset: SiriScenarioLoader

    /// A required evaluation: assert it with `expectAllPass`.
    public init(name: String, harness: SiriAppHarness, before: BeforeRun = .none, dataset: SiriScenarioLoader) {
        self.init(name: name, kind: .required, harness: harness, before: before, dataset: dataset)
    }

    init(name: String, kind: EvaluationKind, harness: SiriAppHarness, before: BeforeRun, dataset: SiriScenarioLoader) {
        self.name = kind.tag(name)
        self.kind = kind
        self.harness = harness
        self.before = before
        self.dataset = dataset
    }

    /// The question without the app's name, repeated, to measure whether Siri still picks the tool. Informational:
    /// Siri may fairly ask which app you mean, so the summary reports it but never fails on it. Don't assert it.
    public static func appNotNamed(
        name: String, harness: SiriAppHarness, before: BeforeRun = .none, question: ToolQuestion, times: Int,
        scenario: (_ prompt: String) -> SiriScenario
    ) -> ToolEvaluation {
        ToolEvaluation(
            name: name, kind: .informational, harness: harness, before: before,
            dataset: .repeating(times: times) { scenario(question.withoutAppName) }
        )
    }

    /// The app launched with `switches` that break the tool (refresh off, signed out), so the reply check must
    /// fail. Use the same scenario as the required evaluation and assert it with `expectAllFail(.siriResponse)`.
    public static func negativeControl(
        name: String, harness: SiriAppHarness, turningOn switches: EvalSwitch..., before: BeforeRun = .none,
        dataset: SiriScenarioLoader
    ) -> ToolEvaluation {
        precondition(!switches.isEmpty, "A negative control breaks the app: turn on at least one EvalSwitch")
        return ToolEvaluation(
            name: name, kind: .negativeControl, harness: harness.turningOn(switches), before: before, dataset: dataset
        )
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
