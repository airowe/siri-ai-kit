import Testing
@testable import SiriAIKit

struct ToolErrorReplyTests {
    static let appName = "Siri Spike"

    @Test(arguments: [
        (ToolError.signedOut, "Open Siri Spike to sign in again."),
        (.keychain(-25308), "Open Siri Spike to sign in again."),
        (.timedOut, "Couldn't reach Siri Spike right now."),
        (.unreachable, "Couldn't reach Siri Spike right now."),
        (.rejected(status: 500), "Siri Spike couldn't do that right now."),
        (.invalidResponse, "Siri Spike couldn't do that right now."),
    ])
    func defaultReplies(error: ToolError, expected: String) {
        #expect(error.reply(appName: Self.appName) == expected)
    }

    @Test func overrideReplaces() {
        var replies = ToolReplies.default
        replies.signedOut = { "Sign in to \($0) on your phone." }
        #expect(ToolError.signedOut.reply(appName: Self.appName, overrides: replies) == "Sign in to Siri Spike on your phone.")
        #expect(ToolError.timedOut.reply(appName: Self.appName, overrides: replies) == "Couldn't reach Siri Spike right now.")
    }
}
