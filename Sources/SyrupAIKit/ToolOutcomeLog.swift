import Foundation

/// Records what each tool call did ("succeeded (served from cache)", "unreachable", "timed out"),
/// so an evaluation can check what the tools did as well as what Siri said.
///
/// The log keeps the calls since it was last cleared, oldest first. SyrupAIEvalKit launches the app with
/// `clearArgument` before every Siri run, so each run reads only its own calls.
public struct ToolOutcomeLog: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// - Parameter arguments: the process's launch arguments. With `clearArgument` among them, the log is cleared
    ///   the first time it's made in this process, before any call is recorded.
    public init(
        defaults: UserDefaults, key: String = "syrupAIKit.toolOutcomes",
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults
        self.key = key
        if arguments.contains(Self.clearArgument), LaunchClearing.claim(defaults: defaults, key: key) {
            clear()
        }
    }

    public static let standard = ToolOutcomeLog(defaults: .standard)

    /// The launch argument SyrupAIEvalKit passes so the app starts each run with an empty log.
    public static let clearArgument = "--siri-ai-eval-clear-outcomes"
    /// The most calls the log keeps; older calls are dropped and counted.
    public static let callLimit = 20
    static let callSeparator = "; "

    /// The accessibility identifier SyrupAIEvalKit reads the outcome from.
    public static let accessibilityIdentifier = "siri-ai-tool-outcome"
    static let labelPrefix = "Tool calls: "
    static let legacyLabelPrefix = "Last tool call: "

    /// The text to show under `accessibilityIdentifier`, if you build your own view instead of `ToolOutcomeView`.
    public static func label(for log: ToolOutcomeLog = .standard) -> String { labelPrefix + log.summary }

    /// The outcome inside a label made by `label(for:)`.
    public static func outcome(fromLabel label: String) -> String {
        for prefix in [labelPrefix, legacyLabelPrefix] where label.hasPrefix(prefix) {
            return String(label.dropFirst(prefix.count))
        }
        return label
    }

    /// Every call since the log was last cleared, oldest first, each with its time.
    public var calls: [String] { stored.calls }

    /// The newest call, or "none".
    public var last: String { calls.last ?? "none" }

    /// Every call, oldest first, separated by "; ", or "none". Says how many older calls were dropped, if any.
    public var summary: String {
        let stored = stored
        guard !stored.calls.isEmpty else { return "none" }
        let dropped = switch stored.dropped {
        case 0: ""
        case 1: "1 earlier call not shown" + Self.callSeparator
        default: "\(stored.dropped) earlier calls not shown" + Self.callSeparator
        }
        return dropped + stored.calls.joined(separator: Self.callSeparator)
    }

    /// Forgets every call.
    public func clear() {
        Self.lock.withLock { defaults.removeObject(forKey: key) }
    }

    /// Adds a detail to the outcome of the `SiriTool` run this code is part of, for example "served from cache".
    ///
    /// Notes belong to the run whose operation made them, whichever log you call this on. Notes made outside
    /// a run, or after its outcome was recorded (a late finish after a timeout), are dropped.
    public func note(_ detail: String) {
        RunNotes.current?.add(detail)
    }

    func record(_ outcome: String, notes: [String] = []) {
        let detail = notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))"
        let call = "\(outcome)\(detail) at \(Date.now.formatted(date: .omitted, time: .standard))"
        Self.lock.withLock {
            var stored = stored
            stored.calls.append(call)
            let excess = stored.calls.count - Self.callLimit
            if excess > 0 {
                stored.calls.removeFirst(excess)
                stored.dropped += excess
            }
            defaults.set(["calls": stored.calls, "dropped": stored.dropped] as [String: Any], forKey: key)
        }
    }

    private static let lock = NSLock()

    private var stored: (calls: [String], dropped: Int) {
        let value = defaults.dictionary(forKey: key)
        return (value?["calls"] as? [String] ?? [], value?["dropped"] as? Int ?? 0)
    }
}

/// Remembers which logs this process has already cleared for `clearArgument`, so a log made later in the same
/// launch keeps the calls recorded so far.
private enum LaunchClearing {
    nonisolated(unsafe) private static var cleared: [(defaults: UserDefaults, key: String)] = []
    private static let lock = NSLock()

    /// True the first time it's called for this log in this process.
    static func claim(defaults: UserDefaults, key: String) -> Bool {
        lock.withLock {
            guard !cleared.contains(where: { $0.defaults === defaults && $0.key == key }) else { return false }
            cleared.append((defaults, key))
            return true
        }
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
