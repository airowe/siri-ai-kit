import Foundation

/// Records what the last tool call did ("used saved token", "refreshed after 401", "signed out"),
/// so an evaluation can tell a real refresh from a token that hadn't expired yet.
public struct ToolOutcomeLog: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "siriAIKit.lastToolOutcome") {
        self.defaults = defaults
        self.key = key
    }

    public static let standard = ToolOutcomeLog(defaults: .standard)

    /// The accessibility identifier SiriAIEvalKit reads the outcome from.
    public static let accessibilityIdentifier = "siri-ai-tool-outcome"
    static let labelPrefix = "Last tool call: "

    /// The text to show under `accessibilityIdentifier`, if you build your own view instead of `ToolOutcomeView`.
    public static func label(for log: ToolOutcomeLog = .standard) -> String { labelPrefix + log.last }

    /// The outcome inside a label made by `label(for:)`.
    public static func outcome(fromLabel label: String) -> String {
        label.hasPrefix(labelPrefix) ? String(label.dropFirst(labelPrefix.count)) : label
    }

    public var last: String { defaults.string(forKey: key) ?? "none" }

    func record(_ outcome: String) {
        defaults.set("\(outcome) at \(Date.now.formatted(date: .omitted, time: .standard))", forKey: key)
    }
}
