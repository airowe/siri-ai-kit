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

    /// Adds a detail to the outcome of the `SiriTool` run this code is part of, for example "refreshed after 401".
    ///
    /// Notes belong to the run whose operation made them, whichever log you call this on. Notes made outside
    /// a run, or after its outcome was recorded (a late finish after a timeout), are dropped.
    public func note(_ detail: String) {
        RunNotes.current?.add(detail)
    }

    func record(_ outcome: String, notes: [String] = []) {
        let detail = notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))"
        defaults.set("\(outcome)\(detail) at \(Date.now.formatted(date: .omitted, time: .standard))", forKey: key)
    }
}

/// The notes of one `SiriTool` run, reached from its operation through a task-local.
final class RunNotes: @unchecked Sendable {
    @TaskLocal static var current: RunNotes?

    private let lock = NSLock()
    private var notes: [String] = []
    private var closed = false

    func add(_ detail: String) {
        lock.withLock { if !closed { notes.append(detail) } }
    }

    /// The notes so far; later notes are dropped.
    func close() -> [String] {
        lock.withLock {
            closed = true
            return notes
        }
    }
}
