import Foundation
import Testing
@testable import SiriAIKit

private enum StubError: Error { case any }
private struct WrappedError: Error { let underlying: any Error }

private actor Flag {
    var isSet = false
    func set() { isSet = true }
}

private func waitUntil(_ flag: Flag, within limit: Duration = .seconds(2)) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if await flag.isSet { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await flag.isSet
}

struct SiriToolTests {
    static let appName = "Siri Spike"
    let log = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)

    func tool(
        timeout: Duration = .seconds(10),
        classify: @escaping @Sendable (any Error) -> ToolFailure? = { _ in nil }
    ) -> SiriTool {
        SiriTool(appName: Self.appName, timeout: timeout, outcomes: log, classify: classify)
    }

    @Test func returnsValueAndRecordsSucceeded() async throws {
        #expect(try await tool().run { 42 } == 42)
        #expect(log.last.hasPrefix("succeeded at "))
    }

    @Test(arguments: [
        (StubError.any as any Error, ToolFailure.failed, "failed"),
        (ToolFailure.signedOut, .signedOut, "signed out"),
        (CancellationError(), .timedOut, "timed out"),
        (URLError(.timedOut), .timedOut, "timed out"),
        (URLError(.cancelled), .timedOut, "timed out"),
        (URLError(.notConnectedToInternet), .unreachable, "unreachable"),
        (URLError(.cannotFindHost), .unreachable, "unreachable"),
    ])
    func classifiesThrownErrors(thrown: any Error, expected: ToolFailure, word: String) async {
        await #expect(throws: expected) {
            try await tool().run { () async throws -> Int in throw thrown }
        }
        #expect(log.last.hasPrefix("\(word) at "))
    }

    @Test func classifyWinsOverDefaults() async {
        let t = tool { $0 is URLError ? .signedOut : nil }
        await #expect(throws: ToolFailure.signedOut) {
            try await t.run { () async throws -> Int in throw URLError(.notConnectedToInternet) }
        }
    }

    @Test func classifyCanUnwrap() async {
        let t = tool { (($0 as? WrappedError)?.underlying as? URLError) != nil ? .unreachable : nil }
        await #expect(throws: ToolFailure.unreachable) {
            try await t.run { () async throws -> Int in throw WrappedError(underlying: URLError(.timedOut)) }
        }
    }

    @Test func classifyNilFallsBack() async {
        let t = tool { _ in nil }
        await #expect(throws: ToolFailure.unreachable) {
            try await t.run { () async throws -> Int in throw URLError(.cannotFindHost) }
        }
    }

    @Test func timesOutWithoutCancelling() async {
        let flag = Flag()
        let start = ContinuousClock.now
        await #expect(throws: ToolFailure.timedOut) {
            try await tool(timeout: .milliseconds(200)).run { () async throws -> Int in
                try await Task.sleep(for: .seconds(1))
                await flag.set()
                return 1
            }
        }
        #expect(ContinuousClock.now - start < .milliseconds(700))
        #expect(await waitUntil(flag))
    }

    @Test func callerCancellationTimesOut() async throws {
        let t = tool()
        let task = Task {
            try await t.run { () async throws -> Int in
                try await Task.sleep(for: .seconds(2))
                return 1
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(throws: ToolFailure.timedOut) { try result.get() }
    }

    @Test func lateFinishDoesNotOverwriteOutcome() async throws {
        let flag = Flag()
        _ = try? await tool(timeout: .milliseconds(100)).run { () async throws -> Int in
            try await Task.sleep(for: .milliseconds(300))
            await flag.set()
            return 1
        }
        #expect(await waitUntil(flag))
        try await Task.sleep(for: .milliseconds(50))
        #expect(log.last.hasPrefix("timed out at "))
    }

    @Test func racesResolveOnce() async {
        let t = tool(timeout: .milliseconds(50))
        for _ in 0..<50 {
            do {
                let value = try await t.run { () async throws -> Int in
                    try await Task.sleep(for: .milliseconds(50))
                    return 7
                }
                #expect(value == 7)
            } catch {
                #expect(error == .timedOut)
            }
        }
    }

    @Test func notesAppearInOutcome() async throws {
        let log = log
        _ = try await tool().run { () async throws -> Int in
            log.note("refreshed after 401")
            return 1
        }
        #expect(log.last.hasPrefix("succeeded (refreshed after 401) at "))
    }

    @Test func notesClearedBetweenRuns() async throws {
        let log = log
        let flag = Flag()
        let t = tool(timeout: .milliseconds(100))
        _ = try? await t.run { () async throws -> Int in
            try await Task.sleep(for: .milliseconds(300))
            log.note("late")
            await flag.set()
            return 1
        }
        #expect(await waitUntil(flag))
        _ = try await t.run { 1 }
        #expect(log.last.hasPrefix("succeeded at "))
    }

    @Test func lateNoteDoesNotLeakIntoOverlappingRun() async throws {
        let log = log
        let gate = Flag()
        let noted = Flag()
        let t = tool(timeout: .milliseconds(100))
        _ = try? await t.run { () async throws -> Int in
            while !(await gate.isSet) { try await Task.sleep(for: .milliseconds(10)) }
            log.note("from run A")
            await noted.set()
            return 1
        }
        _ = try await tool().run { () async throws -> Int in
            await gate.set()
            #expect(await waitUntil(noted))
            log.note("from run B")
            return 2
        }
        #expect(log.last.hasPrefix("succeeded (from run B) at "))
    }

    @Test func concurrentNotesAreAllKept() async throws {
        let log = log
        _ = try await tool().run { () async throws -> Int in
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<200 { group.addTask { log.note("n\(index)") } }
            }
            return 1
        }
        #expect(log.last.components(separatedBy: "; ").count == 200)
    }

    @Test func noteOutsideARunIsIgnored() async throws {
        log.note("stray")
        _ = try await tool().run { 1 }
        #expect(log.last.hasPrefix("succeeded at "))
    }

    @Test(arguments: [
        (ToolFailure.signedOut, "Open Siri Spike to sign in again."),
        (.timedOut, "Couldn't reach Siri Spike right now."),
        (.failed, "Siri Spike couldn't do that right now."),
    ])
    func answerReturnsReply(failure: ToolFailure, expected: String) async {
        #expect(await tool().answer { throw failure } == expected)
    }

    @Test func answerReturnsValue() async {
        #expect(await tool().answer { "Your cart has 3 products." } == "Your cart has 3 products.")
    }
}
