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
