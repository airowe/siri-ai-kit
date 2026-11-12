import Foundation
import Testing
@testable import SyrupAIKit

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

struct ToolOutcomeLogTests {
    let defaults = freshDefaults()

    @Test func lastIsNoneInitially() {
        #expect(ToolOutcomeLog(defaults: defaults).last == "none")
    }

    @Test func recordAppendsTime() {
        let log = ToolOutcomeLog(defaults: defaults)
        log.record("read from disk")
        #expect(log.last.hasPrefix("read from disk at "))
        #expect(log.last.count > "read from disk at ".count)
    }
}

struct ToolOutcomeHistoryTests {
    let log = ToolOutcomeLog(defaults: freshDefaults(), arguments: [])

    @Test func noCallsInitially() {
        #expect(log.calls.isEmpty)
        #expect(log.summary == "none")
    }

    @Test func keepsEveryCallOldestFirst() {
        log.record("failed", notes: ["productId 99999"])
        log.record("succeeded")
        #expect(log.calls.count == 2)
        #expect(log.calls[0].hasPrefix("failed (productId 99999) at "))
        #expect(log.calls[1].hasPrefix("succeeded at "))
    }

    @Test func lastIsTheNewestCall() {
        log.record("failed")
        log.record("succeeded")
        #expect(log.last == log.calls[1])
    }

    @Test func summaryListsEveryCallInOrder() {
        log.record("failed", notes: ["productId 99999"])
        log.record("succeeded")
        #expect(log.summary == log.calls.joined(separator: ToolOutcomeLog.callSeparator))
        #expect(log.summary.wholeMatch(of: /failed \(productId 99999\) at .+; succeeded at .+/) != nil)
    }

    @Test func clearEmptiesTheLog() {
        log.record("succeeded")
        log.clear()
        #expect(log.calls.isEmpty)
        #expect(log.last == "none")
    }

    @Test func keepsOnlyTheNewestCallsAndSaysHowManyWereDropped() {
        let total = ToolOutcomeLog.callLimit + 2
        for index in 1...total { log.record("call \(index)") }
        #expect(log.calls.count == ToolOutcomeLog.callLimit)
        #expect(log.calls.first?.hasPrefix("call 3 at ") == true)
        #expect(log.summary.hasPrefix("2 earlier calls not shown; call 3 at "))
    }
}

struct ToolOutcomeClearOnLaunchTests {
    let defaults = freshDefaults()

    @Test func launchArgumentClearsCallsFromEarlierLaunches() {
        let earlier = ToolOutcomeLog(defaults: defaults, arguments: [])
        earlier.record("succeeded")
        #expect(earlier.calls.count == 1)
        let log = ToolOutcomeLog(defaults: defaults, arguments: [ToolOutcomeLog.clearArgument])
        #expect(log.calls.isEmpty)
    }

    @Test func launchArgumentClearsOnlyOncePerProcess() {
        let first = ToolOutcomeLog(defaults: defaults, arguments: [ToolOutcomeLog.clearArgument])
        first.record("failed")
        let second = ToolOutcomeLog(defaults: defaults, arguments: [ToolOutcomeLog.clearArgument])
        #expect(second.calls.count == 1)
    }

    @Test func withoutTheArgumentNothingIsCleared() {
        ToolOutcomeLog(defaults: defaults, arguments: []).record("succeeded")
        #expect(ToolOutcomeLog(defaults: defaults, arguments: ["--other"]).calls.count == 1)
    }

    @Test func argumentIsNamespacedLikeEvalSwitches() {
        #expect(ToolOutcomeLog.clearArgument.hasPrefix("--siri-ai-eval-"))
        #expect(!EvalSwitch("clear-outcomes").isOn(in: [ToolOutcomeLog.clearArgument]))
    }
}

struct ToolOutcomeNotesTests {
    let log = ToolOutcomeLog(defaults: freshDefaults())

    @Test func notesAppearInRecord() {
        log.record("succeeded", notes: ["served from cache", "retried once"])
        #expect(log.last.hasPrefix("succeeded (served from cache; retried once) at "))
    }

    @Test func recordWithoutNotes() {
        log.record("failed")
        #expect(log.last.hasPrefix("failed at "))
    }

    @Test func closedRunDropsLateNotes() {
        let notes = RunNotes()
        notes.add("early")
        #expect(notes.close() == ["early"])
        notes.add("late")
        #expect(notes.close() == ["early"])
    }
}
