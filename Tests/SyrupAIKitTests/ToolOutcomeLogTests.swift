import Foundation
import Testing
@testable import SyrupAIKit

struct ToolOutcomeLogTests {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

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

struct ToolOutcomeNotesTests {
    let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)

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
