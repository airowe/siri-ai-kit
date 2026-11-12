import Foundation
import Testing
@testable import SyrupAIEvalSummary

struct EvalResultParserTests {
    @Test(arguments: [
        (Fixture.cartAllPass, 5, 5, 1.0, 1.0),
        (.cartNegativeControl, 5, 4, 0.0, 0.0),
        (.cartWithIncomplete, 5, 3, 0.6, 1.0),
        (.orderOneIncomplete, 5, 4, 0.8, 1.0),
        (.noToolExpected, 1, 1, 1.0, 1.0),
    ])
    func passRates(fixture: Fixture, runs: Int, complete: Int, apple: Double, real: Double) throws {
        let report = try fixture.report()
        #expect(report.runs.count == runs)
        #expect(report.runs.count { !$0.incomplete } == complete)
        #expect(abs(report.applePassRate - apple) < 0.0001)
        #expect(abs(try #require(report.realPassRate) - real) < 0.0001)
    }

    @Test func nameIsTheEvaluationID() throws {
        #expect(try Fixture.cartWithIncomplete.report().name == "Cart answer with incomplete runs, repeated")
    }

    @Test func incompleteRunsAreDetected() throws {
        let runs = try Fixture.cartWithIncomplete.report().runs
        #expect(runs.map(\.incomplete) == [false, true, false, false, true])
        #expect(runs[1].toolCalls == ["GetCartIntent": false])
        #expect(runs[0].toolCalls == ["GetCartIntent": true])
    }

    @Test func replyIsExtracted() throws {
        let run = try #require(try Fixture.cartAllPass.report().runs.first)
        #expect(run.reply == "From Siri Spike: Your cart has 4 products, $13,037.88: Blue Frock, Generic Motorcycle, iPhone 6, Baseball Ball.")
    }

    @Test func negativeControlFailsTheReplyOnly() throws {
        let run = try Fixture.cartNegativeControl.report().runs[1]
        #expect(run.intentsPassed)
        #expect(!run.replyPassed)
        #expect(!run.incomplete)
    }

    @Test func ignoredReplyWithNoToolCallPasses() throws {
        let run = try #require(try Fixture.noToolExpected.report().runs.first)
        #expect(run.toolCalls.isEmpty)
        #expect(run.replyPassed)
        #expect(run.reply == "Which package? The trail running shoes, the brass desk lamp, or the Ethiopian coffee beans?")
    }

    @Test func laterTurnsContributeToolCalls() throws {
        let runs = try Fixture.cartAfterSayingYes.report().runs
        #expect(runs.map(\.toolCalls) == Array(repeating: ["GetCartIntent": false], count: runs.count))
    }

    @Test func replyIsTheLastTurns() throws {
        let runs = try Fixture.cartAfterSayingYes.report().runs
        #expect(runs[1...].allSatisfy { $0.reply == "What can I help you with?" })
    }

    @Test func runEndingInALaterTurnIsIncomplete() throws {
        let runs = try Fixture.cartAfterSayingYes.report().runs
        #expect(runs.map(\.incomplete) == [true, false, false, false, false])
    }

    @Test(arguments: [
        ("No — not called", "Yes", true),
        ("Yes", "No — not called", true),
        ("No — not called", "No — not called", false),
    ])
    func intentIsCalledWhenAnyTurnCallsIt(firstTurn: String, secondTurn: String, called: Bool) throws {
        let turns = [
            "Turn 2": ["2 · Intent Call": ["· GetCartIntent": secondTurn], "4 · Siri Response": "\"Done.\""],
            "Turn 1": ["2 · Intent Call": ["· GetCartIntent": firstTurn], "3 · Siri Response": "\"Is that OK?\""],
        ]
        let run = try parseSingleRun(response: turns)
        #expect(run.toolCalls == ["GetCartIntent": called])
        #expect(run.reply == "Done.")
    }

    @Test func turnsAreOrderedNumerically() throws {
        let turns = (1...10).reduce(into: [String: [String: String]]()) { turns, number in
            turns["Turn \(number)"] = ["2 · Siri Response": "\"Reply \(number)\""]
        }
        #expect(try parseSingleRun(response: turns).reply == "Reply 10")
    }

    @Test func realPassRateIsNilWhenEveryRunIsIncomplete() {
        let report = EvalReport(name: "x", runs: [EvalRun(toolCalls: [:], reply: nil, intentsPassed: false, replyPassed: false, incomplete: true)])
        #expect(report.realPassRate == nil)
        #expect(report.applePassRate == 0)
    }

    @Test(arguments: ["{}", "not json", #"{"evaluationID":"x","results":[{"Intents":{"kind":"pass"}}]}"#])
    func malformedFileNamesTheFile(contents: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "broken.xcevalresult")
        try Data(contents.utf8).write(to: file)
        #expect(throws: EvalSummaryError.malformed(file: "broken.xcevalresult")) { try EvalResultParser.parse(contentsOf: file) }
    }

    @Test func emptyDirectoryThrowsNoEvaluations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("text".utf8).write(to: directory.appending(path: "notes.txt"))
        #expect(throws: EvalSummaryError.noEvaluations(path: directory.path)) { try EvalResultParser.parseDirectory(directory) }
    }

    @Test func parseDirectoryFindsNestedResults() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appending(path: "a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.cartAllPass.url, to: nested.appending(path: "one.xcevalresult"))
        try FileManager.default.copyItem(at: Fixture.cartWithIncomplete.url, to: directory.appending(path: "two.xcevalresult"))
        let names = try EvalResultParser.parseDirectory(directory).map(\.name).sorted()
        #expect(names == ["Cart answer with incomplete runs, repeated", "Cart contents from the demo API, repeated"])
    }
}

private func parseSingleRun(response: [String: Any]) throws -> EvalRun {
    let responseText = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
    let file: [String: Any] = [
        "evaluationID": "Multi-turn",
        "results": [["Intents": ["kind": "pass"], "Siri Response": ["kind": "pass"], "Response": ["value": responseText]]],
    ]
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "multi-turn.xcevalresult")
    try JSONSerialization.data(withJSONObject: file).write(to: url)
    return try #require(try EvalResultParser.parse(contentsOf: url).runs.first)
}
