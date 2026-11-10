import Foundation
import Testing
@testable import SiriAIEvalSummary

/// Builds a folder shaped like `xcresulttool export attachments` output.
struct ExportFolder {
    let url: URL
    private var entries: [[String: Any]] = []
    private var testIdentifier: String

    init(testIdentifier: String = "refreshesExpiredTokenEveryTime()") throws {
        url = try makeTemporaryDirectory()
        self.testIdentifier = testIdentifier
    }

    mutating func add(_ fixture: Fixture, at timestamp: Double) throws {
        let name = "\(UUID().uuidString).xcevalresult"
        try FileManager.default.copyItem(at: fixture.url, to: url.appending(path: name))
        entries.append(["exportedFileName": name, "suggestedHumanReadableName": "\(fixture.rawValue)_0_X.xcevalresult", "timestamp": timestamp])
    }

    mutating func addOutcome(_ text: String, at timestamp: Double) throws {
        let name = "\(UUID().uuidString).txt"
        try Data(text.utf8).write(to: url.appending(path: name))
        entries.append(["exportedFileName": name, "suggestedHumanReadableName": "siri-ai-eval-outcome_\(UUID().uuidString).txt", "timestamp": timestamp])
    }

    func writeManifest() throws {
        let manifest: [[String: Any]] = [["testIdentifier": testIdentifier, "attachments": entries]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appending(path: "manifest.json"))
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

struct ExportReaderTests {
    static let outcomes = (1...5).map { "refreshed after 401 at 11:3\($0):00 AM" }

    @Test func pairsOutcomesWithRunsInTimeOrder() throws {
        var folder = try ExportFolder()
        defer { folder.remove() }
        for (index, outcome) in Self.outcomes.enumerated().reversed() {
            try folder.addOutcome(outcome, at: Double(100 + index))
        }
        try folder.add(.authWithIncomplete, at: 200)
        try folder.writeManifest()

        let reports = try ExportReader.reports(in: folder.url)
        #expect(reports.count == 1)
        #expect(reports[0].runs.map(\.outcome) == Self.outcomes)
    }

    @Test func leavesOutcomesEmptyWhenCountsDiffer() throws {
        var folder = try ExportFolder()
        defer { folder.remove() }
        try folder.addOutcome(Self.outcomes[0], at: 100)
        try folder.add(.authWithIncomplete, at: 200)
        try folder.writeManifest()

        let report = try #require(try ExportReader.reports(in: folder.url).first)
        #expect(report.runs.allSatisfy { $0.outcome == nil })
        #expect(report.unmatchedOutcomes == [Self.outcomes[0]])
    }

    @Test func worksWithoutAManifest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: Fixture.cartAllPass.url, to: directory.appending(path: "a.xcevalresult"))
        let reports = try ExportReader.reports(in: directory)
        #expect(reports.map(\.runs.count) == [5])
        #expect(reports[0].runs.allSatisfy { $0.outcome == nil })
    }

    @Test func outcomeIsPrinted() throws {
        var folder = try ExportFolder()
        defer { folder.remove() }
        for (index, outcome) in Self.outcomes.enumerated() {
            try folder.addOutcome(outcome, at: Double(100 + index))
        }
        try folder.add(.authWithIncomplete, at: 200)
        try folder.writeManifest()

        let text = SummaryFormatter.text(try ExportReader.reports(in: folder.url))
        #expect(text.contains("reply check: pass | outcome: refreshed after 401 at 11:31:00 AM"))
        #expect(text.contains("outcome: refreshed after 401 at 11:32:00 AM | incomplete"))
    }
}
