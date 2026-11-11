import Foundation
import Testing
@testable import SiriAIEvalSummary

private func run(reply replyPassed: Bool, intents intentsPassed: Bool = true, incomplete: Bool = false) -> EvalRun {
    EvalRun(toolCalls: ["GetCartIntent": intentsPassed], reply: "r", intentsPassed: intentsPassed, replyPassed: replyPassed, incomplete: incomplete)
}

private func report(_ kind: EvaluationKind, _ runs: [EvalRun]) -> EvalReport {
    EvalReport(name: kind.tag("Cart"), runs: runs)
}

private let allPass = [run(reply: true), run(reply: true)]
private let allReplyFail = [run(reply: false), run(reply: false, intents: false)]
private let oneReplyPass = [run(reply: false), run(reply: true)]
private let replyFailPlusCutShortPass = [run(reply: false), run(reply: true, incomplete: true)]
private let onlyCutShort = [run(reply: false, incomplete: true)]

struct EvaluationKindExitPolicyTests {
    @Test(arguments: [
        (allPass, FailOn.any, Int32(1)),
        (allPass, .real, 1),
        (oneReplyPass, .any, 1),
        (oneReplyPass, .real, 1),
        (allReplyFail, .any, 0),
        (allReplyFail, .real, 0),
        (replyFailPlusCutShortPass, .any, 1),
        (replyFailPlusCutShortPass, .real, 0),
        (onlyCutShort, .any, 0),
        (onlyCutShort, .real, 1),
        ([], .any, 1),
        ([], .real, 1),
    ])
    func negativeControlPassesOnlyWhenTheReplyCheckFailed(runs: [EvalRun], failOn: FailOn, expected: Int32) {
        #expect(ExitPolicy.status(for: [report(.negativeControl, runs)], failOn: failOn) == expected)
    }

    @Test(arguments: FailOn.allCases)
    func informationalNeverFails(failOn: FailOn) {
        let reports = [report(.required, allPass), report(.informational, allReplyFail), report(.informational, [])]
        #expect(ExitPolicy.status(for: reports, failOn: failOn) == 0)
    }

    @Test(arguments: FailOn.allCases)
    func requiredStillFailsAlongsideTheOthers(failOn: FailOn) {
        let reports = [report(.required, oneReplyPass), report(.informational, allPass), report(.negativeControl, allReplyFail)]
        #expect(ExitPolicy.status(for: reports, failOn: failOn) == 1)
    }

    @Test(arguments: FailOn.allCases)
    func everyKindAsExpectedPasses(failOn: FailOn) {
        let reports = [report(.required, allPass), report(.informational, oneReplyPass), report(.negativeControl, allReplyFail)]
        #expect(ExitPolicy.status(for: reports, failOn: failOn) == 0)
    }
}

struct EvaluationKindFormatterTests {
    @Test func requiredHasNoKindLine() {
        let text = SummaryFormatter.text([report(.required, allPass)])
        #expect(!text.contains("Informational"))
        #expect(!text.contains("Negative control"))
    }

    @Test func informationalSaysItIsNotCounted() {
        let lines = SummaryFormatter.text([report(.informational, oneReplyPass)]).split(separator: "\n").map(String.init)
        #expect(lines[0] == "Cart [informational]")
        #expect(lines[1] == "  Informational: not counted toward the exit status.")
    }

    @Test(arguments: [
        (allReplyFail, "  Negative control: passes when the reply check fails. Reply check failed in 2 of 2 complete runs: as expected."),
        (oneReplyPass, "  Negative control: passes when the reply check fails. Reply check failed in 1 of 2 complete runs: the checks can't be trusted."),
        (onlyCutShort, "  Negative control: passes when the reply check fails. No complete runs, so it proves nothing."),
    ])
    func negativeControlStatesItsVerdict(runs: [EvalRun], expected: String) {
        let lines = SummaryFormatter.text([report(.negativeControl, runs)]).split(separator: "\n").map(String.init)
        #expect(lines[1] == expected)
    }

    @Test(arguments: EvaluationKind.allCases)
    func jsonIncludesTheKind(kind: EvaluationKind) throws {
        let json = try SummaryFormatter.json([report(kind, allPass)])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(object.first?["kind"] as? String == kind.rawValue)
        #expect(try JSONDecoder().decode([EvalReport].self, from: Data(json.utf8)) == [report(kind, allPass)])
    }
}
