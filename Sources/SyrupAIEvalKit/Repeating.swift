#if os(iOS) && canImport(SiriEvaluations) && canImport(XCTest)
import SiriEvaluations

@available(iOS 27.3, *)
extension SiriScenarioLoader {
    /// The same scenario several times. Siri varies from run to run, so one passing run proves little.
    public static func repeating(times: Int, _ scenario: () -> SiriScenario) -> SiriScenarioLoader {
        let scenarios = (0..<times).map { _ in scenario() }
        return SiriScenarioLoader { scenarios }
    }
}
#endif
