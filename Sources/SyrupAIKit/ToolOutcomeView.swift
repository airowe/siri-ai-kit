#if DEBUG && canImport(SwiftUI)
import SwiftUI

/// Shows what the last tool call did, so Siri Evaluations can read it. Debug builds only.
public struct ToolOutcomeView: View {
    let log: ToolOutcomeLog

    public init(log: ToolOutcomeLog = .standard) {
        self.log = log
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(ToolOutcomeLog.label(for: log))
                .font(.footnote)
                .accessibilityIdentifier(ToolOutcomeLog.accessibilityIdentifier)
        }
    }
}
#endif
