public enum FailOn: String, Sendable, CaseIterable {
    /// Fail when any run fails, incomplete runs included (Xcode's view).
    case any
    /// Fail only when a complete run fails, or no run completed.
    case real
}

public enum ExitPolicy {
    public static func status(for reports: [EvalReport], failOn: FailOn) -> Int32 {
        let allPassed = reports.allSatisfy { report in
            switch failOn {
            case .any: report.applePassRate == 1
            case .real: report.realPassRate == 1
            }
        }
        return allPassed ? 0 : 1
    }
}
