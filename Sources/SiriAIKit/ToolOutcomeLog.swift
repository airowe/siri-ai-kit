import Foundation

/// Records what the last tool call did ("succeeded (refreshed after 401)", "signed out", "timed out"),
/// so an evaluation can check what the tool did as well as what Siri said.
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

    private var notesKey: String { key + ".notes" }

    /// Adds a detail to the current tool call's outcome, for example "refreshed after 401".
    public func note(_ detail: String) {
        defaults.set((defaults.stringArray(forKey: notesKey) ?? []) + [detail], forKey: notesKey)
    }

    func beginRun() {
        defaults.removeObject(forKey: notesKey)
    }

    func record(_ outcome: String) {
        let notes = defaults.stringArray(forKey: notesKey) ?? []
        let detail = notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))"
        defaults.set("\(outcome)\(detail) at \(Date.now.formatted(date: .omitted, time: .standard))", forKey: key)
        beginRun()
    }
}
