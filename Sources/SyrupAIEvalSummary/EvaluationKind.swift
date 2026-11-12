/// What an evaluation's result means for the exit status. SyrupAIEvalKit records the kind as a tag at the end of
/// the evaluation's name, so it survives into the `.xcresult` bundle and Xcode's report shows it too.
public enum EvaluationKind: String, Sendable, Codable, CaseIterable {
    /// Every complete run must pass.
    case required
    /// Reported, never counted toward the exit status: for example the question without the app's name.
    case informational
    /// Passes only when the reply check fails in every run, because the app was broken on purpose first.
    case negativeControl = "negative control"

    public init(evaluationName: String) {
        self = Self.allCases.first { $0 != .required && evaluationName.hasSuffix($0.suffix) } ?? .required
    }

    /// `name` with this kind's tag appended, or unchanged for `.required`.
    public func tag(_ name: String) -> String {
        guard self != .required, EvaluationKind(evaluationName: name) != self else { return name }
        return name + suffix
    }

    var suffix: String { " [\(rawValue)]" }
}
