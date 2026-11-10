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
        log.note("refreshed after 401")
        log.note("retried once")
        log.record("succeeded")
        #expect(log.last.hasPrefix("succeeded (refreshed after 401; retried once) at "))
    }

    @Test func recordClearsNotes() {
        log.note("x")
        log.record("succeeded")
        log.record("failed")
        #expect(log.last.hasPrefix("failed at "))
    }

    @Test func beginRunClearsNotes() {
        log.note("stale")
        log.beginRun()
        log.record("succeeded")
        #expect(log.last.hasPrefix("succeeded at "))
    }
}
