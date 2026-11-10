import Foundation

/// Reads a folder written by `xcresulttool export attachments`.
public enum ExportReader {
    /// Name prefix of the text attachments SiriAIEvalKit records after each run.
    public static let outcomeAttachmentPrefix = "siri-ai-eval-outcome"
    static let manifestName = "manifest.json"

    /// Reports for every evaluation in `folder`, with each run's recorded outcome when the counts line up.
    public static func reports(in folder: URL) throws(EvalSummaryError) -> [EvalReport] {
        let manifestURL = folder.appending(path: manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return try EvalResultParser.parseDirectory(folder)
        }
        let tests: [ManifestTest]
        do {
            tests = try JSONDecoder().decode([ManifestTest].self, from: Data(contentsOf: manifestURL))
        } catch {
            throw .malformed(file: manifestName)
        }

        var reports: [EvalReport] = []
        for test in tests {
            let attachments = test.attachments.sorted { $0.timestamp < $1.timestamp }
            let outcomes = attachments
                .filter { $0.suggestedHumanReadableName.hasPrefix(outcomeAttachmentPrefix) }
                .map { (try? String(contentsOf: folder.appending(path: $0.exportedFileName), encoding: .utf8)) ?? "" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var testReports: [EvalReport] = []
            for attachment in attachments where attachment.exportedFileName.hasSuffix(".\(EvalResultParser.resultExtension)") {
                testReports.append(try EvalResultParser.parse(contentsOf: folder.appending(path: attachment.exportedFileName)))
            }
            reports += paired(testReports, with: outcomes)
        }
        guard !reports.isEmpty else { throw .noEvaluations(path: folder.path) }
        return reports
    }

    static func paired(_ reports: [EvalReport], with outcomes: [String]) -> [EvalReport] {
        guard !outcomes.isEmpty, var first = reports.first else { return reports }
        if reports.count == 1, first.runs.count == outcomes.count {
            for index in first.runs.indices {
                first.runs[index].outcome = outcomes[index]
            }
        } else {
            first.unmatchedOutcomes = outcomes
        }
        return [first] + reports.dropFirst()
    }

    struct ManifestTest: Decodable {
        let attachments: [Attachment]
    }

    struct Attachment: Decodable {
        let exportedFileName: String
        let suggestedHumanReadableName: String
        let timestamp: Double
    }
}
