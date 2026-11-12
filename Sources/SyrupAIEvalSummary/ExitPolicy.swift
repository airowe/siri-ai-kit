public enum FailOn: String, Sendable, CaseIterable {
    /// Fail when any run fails, incomplete runs included (Xcode's view).
    case any
    /// Fail only when a complete run fails, or no run completed.
    case real
}

public enum ExitPolicy {
    public static func status(for reports: [EvalReport], failOn: FailOn) -> Int32 {
        reports.allSatisfy { passes($0, failOn: failOn) } ? 0 : 1
    }

    static func passes(_ report: EvalReport, failOn: FailOn) -> Bool {
        switch (report.kind, failOn) {
        case (.informational, _): true
        case (.required, .any): report.applePassRate == 1
        case (.required, .real): report.realPassRate == 1
        case (.negativeControl, .any): !report.runs.isEmpty && report.runs.allSatisfy { !$0.replyPassed }
        case (.negativeControl, .real): report.completeRunCount > 0 && report.replyFailedCompleteCount == report.completeRunCount
        }
    }
}
