import Testing
@testable import SyrupAIKit

struct ToolFailureReplyTests {
    static let appName = "Siri Spike"

    @Test(arguments: [
        (ToolFailure.timedOut, "Couldn't reach Siri Spike right now."),
        (.unreachable, "Couldn't reach Siri Spike right now."),
        (.failed, "Siri Spike couldn't do that right now."),
    ])
    func defaultReplies(failure: ToolFailure, expected: String) {
        #expect(failure.reply(appName: Self.appName) == expected)
    }

    @Test func overrideReplaces() {
        var replies = ToolReplies.default
        replies.unreachable = { "\($0) is offline." }
        #expect(ToolFailure.unreachable.reply(appName: Self.appName, overrides: replies) == "Siri Spike is offline.")
        #expect(ToolFailure.failed.reply(appName: Self.appName, overrides: replies) == "Siri Spike couldn't do that right now.")
        #expect(ToolFailure.timedOut.reply(appName: Self.appName, overrides: replies) == "Siri Spike is offline.")
    }

    @Test func customRepliesCoverEveryFailure() {
        let replies = ToolReplies(unreachable: { "\($0) is offline." }, failed: { "\($0) hit a problem." })
        #expect(ToolFailure.timedOut.reply(appName: Self.appName, overrides: replies) == "Siri Spike is offline.")
        #expect(ToolFailure.unreachable.reply(appName: Self.appName, overrides: replies) == "Siri Spike is offline.")
        #expect(ToolFailure.failed.reply(appName: Self.appName, overrides: replies) == "Siri Spike hit a problem.")
    }
}
