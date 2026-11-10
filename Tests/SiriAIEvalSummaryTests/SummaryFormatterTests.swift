import Foundation
import Testing
@testable import SiriAIEvalSummary

struct SummaryFormatterTests {
    @Test func textShowsEveryField() throws {
        let text = SummaryFormatter.text([try Fixture.authWithIncomplete.report()])
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.first == "Cart after the access token expires, repeated")
        #expect(lines.filter { $0.contains("Run ") }.count == 5)
        #expect(lines.contains { $0.hasPrefix("  Run 1: GetCartIntent: yes") && $0.contains("reply check: pass") && !$0.contains("incomplete") })
        #expect(lines.contains { $0.hasPrefix("  Run 2: GetCartIntent: no") && $0.hasSuffix("incomplete") })
        #expect(lines.contains { $0.hasPrefix("  Run 5:") && $0.hasSuffix("incomplete") })
        #expect(text.contains(#"reply: "From Siri Spike: Your cart has 4 products"#))
        #expect(lines.contains("  Apple pass rate: 60%"))
        #expect(lines.contains("  Real pass rate: 100% (3 of 3 complete runs)"))
        let negative = SummaryFormatter.text([try Fixture.cartNegativeControl.report()])
        #expect(negative.contains("  Real pass rate: 0% (0 of 4 complete runs)"))
    }

    @Test func intentsCheckIsShown() throws {
        let lines = SummaryFormatter.text([try Fixture.cartNegativeControl.report()]).split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("  Run 1:") && $0.contains("intents check: fail | reply check: fail") })
        #expect(lines.contains { $0.hasPrefix("  Run 2:") && $0.contains("intents check: pass | reply check: fail") })
    }

    @Test func noToolCallsAndNoCompleteRunsAreStated() {
        let report = EvalReport(name: "Empty", runs: [EvalRun(toolCalls: [:], reply: nil, intentsPassed: false, replyPassed: false, incomplete: true)])
        let text = SummaryFormatter.text([report])
        #expect(text.contains("  Run 1: no tool calls | no reply | intents check: fail | reply check: fail | incomplete"))
        #expect(text.contains("  Real pass rate: n/a (no complete runs)"))
    }

    @Test func jsonRoundTrips() throws {
        let reports = try Fixture.allCases.map { try $0.report() }
        let json = try SummaryFormatter.json(reports)
        let decoded = try JSONDecoder().decode([EvalReport].self, from: Data(json.utf8))
        #expect(decoded == reports)
    }
}

struct ExitPolicyTests {
    @Test(arguments: [
        (Fixture.cartAllPass, FailOn.any, Int32(0)),
        (.cartAllPass, .real, 0),
        (.authWithIncomplete, .any, 1),
        (.authWithIncomplete, .real, 0),
        (.cartNegativeControl, .real, 1),
        (.cartNegativeControl, .any, 1),
    ])
    func exitStatus(fixture: Fixture, failOn: FailOn, expected: Int32) throws {
        #expect(ExitPolicy.status(for: [try fixture.report()], failOn: failOn) == expected)
    }

    @Test func everyReportMustPass() throws {
        let reports = [try Fixture.cartAllPass.report(), try Fixture.cartNegativeControl.report()]
        #expect(ExitPolicy.status(for: reports, failOn: .real) == 1)
    }

    @Test func allIncompleteFailsUnderReal() {
        let report = EvalReport(name: "x", runs: [EvalRun(toolCalls: [:], reply: nil, intentsPassed: false, replyPassed: false, incomplete: true)])
        #expect(ExitPolicy.status(for: [report], failOn: .real) == 1)
    }
}
