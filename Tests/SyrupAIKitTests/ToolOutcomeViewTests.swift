import Foundation
import Testing
@testable import SyrupAIKit

struct ToolOutcomeLabelTests {
    @Test func labelShowsEveryCall() {
        let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(ToolOutcomeLog.label(for: log) == "Tool calls: none")
        log.record("failed")
        log.record("served from cache")
        #expect(ToolOutcomeLog.label(for: log).wholeMatch(of: /Tool calls: failed at .+; served from cache at .+/) != nil)
    }

    @Test(arguments: [
        "Tool calls: failed at 9:00:00 AM; read from disk at 9:00:05 AM",
        "Last tool call: failed at 9:00:00 AM; read from disk at 9:00:05 AM",
    ])
    func outcomeIsReadBackFromTheLabel(label: String) {
        #expect(ToolOutcomeLog.outcome(fromLabel: label) == "failed at 9:00:00 AM; read from disk at 9:00:05 AM")
    }

    @Test func outcomeOfAnUnprefixedLabelIsTheLabel() {
        #expect(ToolOutcomeLog.outcome(fromLabel: "something else") == "something else")
    }

    @Test func identifierMatchesTheHarness() {
        #expect(ToolOutcomeLog.accessibilityIdentifier == "siri-ai-tool-outcome")
    }
}
