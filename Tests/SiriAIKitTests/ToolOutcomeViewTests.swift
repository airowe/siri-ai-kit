import Foundation
import Testing
@testable import SiriAIKit

struct ToolOutcomeLabelTests {
    @Test func labelShowsTheLastOutcome() {
        let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(ToolOutcomeLog.label(for: log) == "Last tool call: none")
        log.record("served from cache")
        #expect(ToolOutcomeLog.label(for: log).hasPrefix("Last tool call: served from cache at "))
    }

    @Test func outcomeIsReadBackFromTheLabel() {
        #expect(ToolOutcomeLog.outcome(fromLabel: "Last tool call: read from disk at 9:00:00 AM") == "read from disk at 9:00:00 AM")
        #expect(ToolOutcomeLog.outcome(fromLabel: "something else") == "something else")
    }

    @Test func identifierMatchesTheHarness() {
        #expect(ToolOutcomeLog.accessibilityIdentifier == "siri-ai-tool-outcome")
    }
}
