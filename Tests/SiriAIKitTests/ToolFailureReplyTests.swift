import Testing
@testable import SiriAIKit

struct ToolFailureReplyTests {
    static let appName = "Siri Spike"

    @Test(arguments: [
        (ToolFailure.signedOut, "Open Siri Spike to sign in again."),
        (.timedOut, "Couldn't reach Siri Spike right now."),
        (.unreachable, "Couldn't reach Siri Spike right now."),
        (.failed, "Siri Spike couldn't do that right now."),
    ])
    func defaultReplies(failure: ToolFailure, expected: String) {
        #expect(failure.reply(appName: Self.appName) == expected)
    }

    @Test func overrideReplaces() {
        var replies = ToolReplies.default
        replies.signedOut = { "Sign in to \($0) on your phone." }
        #expect(ToolFailure.signedOut.reply(appName: Self.appName, overrides: replies) == "Sign in to Siri Spike on your phone.")
        #expect(ToolFailure.timedOut.reply(appName: Self.appName, overrides: replies) == "Couldn't reach Siri Spike right now.")
    }
}
