/// What Siri says when a tool fails. Each closure receives the app's name.
public struct ToolReplies: Sendable {
    public var signedOut: @Sendable (String) -> String
    public var unreachable: @Sendable (String) -> String
    public var failed: @Sendable (String) -> String

    public init(
        signedOut: @escaping @Sendable (String) -> String,
        unreachable: @escaping @Sendable (String) -> String,
        failed: @escaping @Sendable (String) -> String
    ) {
        self.signedOut = signedOut
        self.unreachable = unreachable
        self.failed = failed
    }

    public static let `default` = ToolReplies(
        signedOut: { "Open \($0) to sign in again." },
        unreachable: { "Couldn't reach \($0) right now." },
        failed: { "\($0) couldn't do that right now." }
    )
}

extension ToolError {
    /// A sentence for the tool's dialog, so the person hears what went wrong instead of a generic failure.
    public func reply(appName: String, overrides: ToolReplies = .default) -> String {
        switch self {
        case .signedOut, .keychain: overrides.signedOut(appName)
        case .timedOut, .unreachable: overrides.unreachable(appName)
        case .rejected, .invalidResponse: overrides.failed(appName)
        }
    }
}
