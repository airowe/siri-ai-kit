import Foundation

public enum SummaryFormatter {
    public static func text(_ reports: [EvalReport]) -> String {
        reports.map(text(for:)).joined(separator: "\n\n") + "\n"
    }

    public static func json(_ reports: [EvalReport]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(reports), as: UTF8.self)
    }

    static func text(for report: EvalReport) -> String {
        var lines = [report.name]
        for (index, run) in report.runs.enumerated() {
            lines.append("  Run \(index + 1): " + fields(of: run).joined(separator: " | "))
        }
        if !report.unmatchedOutcomes.isEmpty {
            lines.append("  Outcomes not matched to runs: " + report.unmatchedOutcomes.joined(separator: "; "))
        }
        lines.append("  Apple pass rate: \(percent(report.applePassRate))")
        let passedComplete = report.runs.count { !$0.incomplete && $0.passed }
        lines.append(
            report.realPassRate.map {
                "  Real pass rate: \(percent($0)) (\(passedComplete) of \(report.completeRunCount) complete runs)"
            } ?? "  Real pass rate: n/a (no complete runs)"
        )
        return lines.joined(separator: "\n")
    }

    static func fields(of run: EvalRun) -> [String] {
        let calls = run.toolCalls.isEmpty
            ? "no tool calls"
            : run.toolCalls.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value ? "yes" : "no")" }.joined(separator: ", ")
        var fields = [
            calls,
            run.reply.map { "reply: \"\($0)\"" } ?? "no reply",
            "intents check: \(run.intentsPassed ? "pass" : "fail")",
            "reply check: \(run.replyPassed ? "pass" : "fail")",
        ]
        if let outcome = run.outcome { fields.append("outcome: \(outcome)") }
        if run.incomplete { fields.append("incomplete") }
        return fields
    }

    static func percent(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }
}
