import XCTest
#if canImport(AppIntentsTesting)
import AppIntentsTesting
#endif
#if canImport(Evaluations)
import Evaluations
#endif
#if canImport(SiriEvaluations)
import SiriEvaluations
#endif

/// Spike: which of Apple's Siri testing frameworks import, link and run on the Simulator.
final class FrameworkProbeTests: XCTestCase {
    private let bundleIdentifier = "com.example.syrupaikit"

    func testReportWhatImports() {
        var available: [String] = []
        #if canImport(AppIntentsTesting)
        available.append("AppIntentsTesting")
        #endif
        #if canImport(Evaluations)
        available.append("Evaluations")
        #endif
        #if canImport(SiriEvaluations)
        available.append("SiriEvaluations")
        #endif
        print("SPIKE imports: \(available)")
    }

    #if canImport(AppIntentsTesting)
    /// Runs GetCartIntent directly, without Siri.
    @MainActor
    func testAppIntentsTestingRunsCartIntent() async throws {
        XCUIApplication(bundleIdentifier: bundleIdentifier).launch()
        try await Task.sleep(for: .seconds(5))
        let definition = IntentDefinitions(bundleIdentifier: bundleIdentifier).intents["GetCartIntent"]
        print("SPIKE AppIntentsTesting definition: \(definition.identifier)")
        let result = try await definition.makeIntent().run()
        let value: String = try result.value
        print("SPIKE AppIntentsTesting result: \(value)")
        XCTAssertTrue(value.localizedCaseInsensitiveContains("motorcycle"), value)
    }
    #endif

    #if canImport(Evaluations)
    func testEvaluationsTypesWork() throws {
        let expectation = TrajectoryExpectation(expected: "GetCartIntent")
        let data = try JSONEncoder().encode(expectation)
        print("SPIKE Evaluations TrajectoryExpectation: \(String(decoding: data, as: UTF8.self))")
        XCTAssertFalse(data.isEmpty)
    }
    #endif
}
