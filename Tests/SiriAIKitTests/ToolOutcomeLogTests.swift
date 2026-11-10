import Foundation
import Testing
@testable import SiriAIKit

struct ToolOutcomeLogTests {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

    @Test func lastIsNoneInitially() {
        #expect(ToolOutcomeLog(defaults: defaults).last == "none")
    }

    @Test func recordAppendsTime() {
        let log = ToolOutcomeLog(defaults: defaults)
        log.record("used saved token")
        #expect(log.last.hasPrefix("used saved token at "))
        #expect(log.last.count > "used saved token at ".count)
    }
}

struct ToolOutcomeNotesTests {
    let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)

    @Test func notesAppearInRecord() {
        log.record("succeeded", notes: ["refreshed after 401", "retried once"])
        #expect(log.last.hasPrefix("succeeded (refreshed after 401; retried once) at "))
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
