#if os(iOS) && canImport(SiriEvaluations) && canImport(XCTest)
import Evaluations
import SiriEvaluations
import Testing

public enum SiriMetric: Sendable, CaseIterable {
    /// Siri called (or avoided) the intents the scenario expects.
    case intents
    /// Siri's reply matched the scenario's expectation.
    case siriResponse
}

/// Records one failure per metric whose mean over the evaluation's runs is below 1.
@available(iOS 27.3, *)
public func expectAllPass(_ metrics: SiriMetric..., sourceLocation: SourceLocation = #_sourceLocation) throws {
    expectMean(of: metrics, toBe: 1, sourceLocation: sourceLocation)
}

/// For a negative control: records one failure per metric that passed in any run. A run the harness cut short
/// also scores as failed here, so confirm with `syrup-ai-eval summarize --fail-on real` that a complete run failed.
@available(iOS 27.3, *)
public func expectAllFail(_ metrics: SiriMetric..., sourceLocation: SourceLocation = #_sourceLocation) throws {
    expectMean(of: metrics, toBe: 0, sourceLocation: sourceLocation)
}

@available(iOS 27.3, *)
private func expectMean(of metrics: [SiriMetric], toBe expected: Double, sourceLocation: SourceLocation) {
    let result = EvaluationContext.current.result
    for metric in metrics {
        switch metric {
        case .intents:
            let mean = result.aggregateValue(.mean(of: .intentsAllPass))
            #expect(mean == expected, "intentsAllPass mean was \(String(describing: mean))", sourceLocation: sourceLocation)
        case .siriResponse:
            let mean = result.aggregateValue(.mean(of: .siriResponseAllPass))
            #expect(mean == expected, "siriResponseAllPass mean was \(String(describing: mean))", sourceLocation: sourceLocation)
        }
    }
}
#endif
