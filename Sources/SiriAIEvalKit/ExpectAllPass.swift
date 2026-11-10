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
    let result = EvaluationContext.current.result
    for metric in metrics {
        switch metric {
        case .intents:
            let mean = result.aggregateValue(.mean(of: .intentsAllPass))
            #expect(mean == 1, "intentsAllPass mean was \(String(describing: mean))", sourceLocation: sourceLocation)
        case .siriResponse:
            let mean = result.aggregateValue(.mean(of: .siriResponseAllPass))
            #expect(mean == 1, "siriResponseAllPass mean was \(String(describing: mean))", sourceLocation: sourceLocation)
        }
    }
}
#endif
