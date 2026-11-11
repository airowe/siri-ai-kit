import Testing
@testable import SiriAIEvalSummary

private let expectedTool = "GetOrderStatusIntent"
private let otherTool = "SearchOrdersIntent"

private func run(
    calls: [String: Bool], intentsPassed: Bool, replyPassed: Bool, incomplete: Bool = false
) -> EvalRun {
    EvalRun(toolCalls: calls, reply: "Your shoes arrive today.", intentsPassed: intentsPassed, replyPassed: replyPassed, incomplete: incomplete)
}

struct AnsweredWithoutToolTests {
    @Test(arguments: [
        (run(calls: [expectedTool: false], intentsPassed: false, replyPassed: true), true),
        (run(calls: [expectedTool: true], intentsPassed: true, replyPassed: true), false),
        (run(calls: [expectedTool: false], intentsPassed: false, replyPassed: false), false),
        (run(calls: [expectedTool: false], intentsPassed: false, replyPassed: true, incomplete: true), false),
        (run(calls: [:], intentsPassed: true, replyPassed: true), false),
        (run(calls: [expectedTool: true, otherTool: false], intentsPassed: false, replyPassed: true), true),
    ])
    func flagsRightReplyWithoutExpectedTool(run: EvalRun, expected: Bool) {
        #expect(run.answeredWithoutTool == expected)
    }

    @Test func reportCountsCompleteRunsAnsweredWithoutTool() {
        let report = EvalReport(name: "Order status", runs: [
            run(calls: [expectedTool: false], intentsPassed: false, replyPassed: true),
            run(calls: [expectedTool: true], intentsPassed: true, replyPassed: true),
            run(calls: [expectedTool: false], intentsPassed: false, replyPassed: true),
            run(calls: [expectedTool: false], intentsPassed: false, replyPassed: true, incomplete: true),
        ])
        #expect(report.answeredWithoutToolCount == 2)
        let lines = SummaryFormatter.text([report]).split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.hasPrefix("  Run 1:") && $0.hasSuffix("| answered without calling the tool") })
        #expect(lines.contains { $0.hasPrefix("  Run 2:") && !$0.contains("answered without") })
        #expect(lines.contains(
            "  Answered without calling the tool: 2 of 3 complete runs. Siri likely answered from the Spotlight index; index only what identifies a record."
        ))
    }

    @Test func noLineWhenEveryRunCalledTheTool() throws {
        let text = SummaryFormatter.text([try Fixture.cartAllPass.report()])
        #expect(!text.contains("answered without"))
        #expect(!text.contains("Answered without"))
    }
}
