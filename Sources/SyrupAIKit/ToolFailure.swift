/// Why a tool couldn't answer, in the terms Siri speaks to the person.
public enum ToolFailure: Error, Equatable, Sendable {
    case timedOut
    case unreachable
    case failed
}
