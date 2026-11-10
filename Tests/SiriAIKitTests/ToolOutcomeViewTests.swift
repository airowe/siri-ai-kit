import Foundation
import Testing
@testable import SiriAIKit

struct ToolOutcomeLabelTests {
    @Test func labelShowsTheLastOutcome() {
        let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(ToolOutcomeLog.label(for: log) == "Last tool call: none")
        log.record("refreshed after 401")
        #expect(ToolOutcomeLog.label(for: log).hasPrefix("Last tool call: refreshed after 401 at "))
    }

    @Test func outcomeIsReadBackFromTheLabel() {
        #expect(ToolOutcomeLog.outcome(fromLabel: "Last tool call: used saved token at 9:00:00 AM") == "used saved token at 9:00:00 AM")
        #expect(ToolOutcomeLog.outcome(fromLabel: "something else") == "something else")
    }

    @Test func identifierMatchesTheHarness() {
        #expect(ToolOutcomeLog.accessibilityIdentifier == "siri-ai-tool-outcome")
    }
}
