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

    public var last: String { defaults.string(forKey: key) ?? "none" }

    func record(_ outcome: String) {
        defaults.set("\(outcome) at \(Date.now.formatted(date: .omitted, time: .standard))", forKey: key)
    }
}
