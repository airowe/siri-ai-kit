import Foundation

public enum EvalResultParser {
    static let incompleteMarker = "the run ended before all of its results arrived"
    static let resultExtension = "xcevalresult"

    public static func parse(contentsOf url: URL) throws(EvalSummaryError) -> EvalReport {
        let malformed = EvalSummaryError.malformed(file: url.lastPathComponent)
        do {
            let file = try JSONDecoder().decode(ResultFile.self, from: Data(contentsOf: url))
            return EvalReport(name: file.evaluationID, runs: try file.results.map(run(from:)))
        } catch {
            throw malformed
        }
    }

    /// Every `.xcevalresult` under `url`, at any depth, in path order.
    public static func parseDirectory(_ url: URL) throws(EvalSummaryError) -> [EvalReport] {
        let files = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects ?? [])
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == resultExtension }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw .noEvaluations(path: url.path) }
        var reports: [EvalReport] = []
        for file in files {
            reports.append(try parse(contentsOf: file))
        }
        return reports
    }

    static func run(from result: ResultFile.Result) throws -> EvalRun {
        let response = try JSONSerialization.jsonObject(with: Data(result.response.value.utf8)) as? [String: Any]
        let turn = response?["Turn 1"] as? [String: Any] ?? [:]

        var calls: [String: String] = [:]
        for (key, value) in turn where key.hasSuffix("Intent Call") {
            for (intent, outcome) in value as? [String: String] ?? [:] {
                calls[intent.replacing(/^·\s*/, with: "")] = outcome
            }
        }
        let reply = turn.first { $0.key.hasSuffix("Siri Response") }
            .flatMap { $0.value as? String }
            .map(unquote)

        let incomplete = calls.values.contains { $0.contains(incompleteMarker) }
            || reply?.contains(incompleteMarker) == true
        return EvalRun(
            toolCalls: calls.mapValues { $0 == "Yes" },
            reply: reply,
            intentsPassed: passed(result.intents.kind),
            replyPassed: passed(result.siriResponse.kind),
            incomplete: incomplete
        )
    }

    static func passed(_ kind: String) -> Bool { kind == "pass" || kind == "ignore" }

    static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }
}

struct ResultFile: Decodable {
    let evaluationID: String
    let results: [Result]

    struct Result: Decodable {
        let intents: Score
        let siriResponse: Score
        let response: Value

        enum CodingKeys: String, CodingKey {
            case intents = "Intents"
            case siriResponse = "Siri Response"
            case response = "Response"
        }
    }

    struct Score: Decodable { let kind: String }
    struct Value: Decodable { let value: String }
}
