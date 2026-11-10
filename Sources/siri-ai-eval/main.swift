#if os(macOS)
import Foundation
import SiriAIEvalSummary

let usage = "usage: siri-ai-eval summarize <path.xcresult> [--json] [--fail-on any|real]"

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

struct Options {
    var path: String
    var json = false
    var failOn = FailOn.any
}

func parseOptions(_ arguments: [String]) -> Options? {
    guard arguments.first == "summarize", arguments.count >= 2 else { return nil }
    var options = Options(path: arguments[1])
    var rest = arguments.dropFirst(2)[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--json":
            options.json = true
        case "--fail-on":
            guard let value = rest.popFirst(), let failOn = FailOn(rawValue: value) else { return nil }
            options.failOn = failOn
        default:
            return nil
        }
    }
    return options
}

func exportAttachments(of resultBundle: String, to folder: URL) -> Int32 {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/xcrun")
    process.arguments = ["xcresulttool", "export", "attachments", "--path", resultBundle, "--output-path", folder.path]
    process.standardOutput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
}

guard let options = parseOptions(Array(CommandLine.arguments.dropFirst())) else {
    fail(usage, status: 64)
}
guard FileManager.default.fileExists(atPath: options.path) else {
    fail("No result bundle at \(options.path)", status: 2)
}

let folder = FileManager.default.temporaryDirectory.appending(path: "siri-ai-eval-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: folder) }
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
} catch {
    fail("Couldn't create \(folder.path)", status: 2)
}

let exportStatus = exportAttachments(of: options.path, to: folder)
guard exportStatus == 0 else {
    try? FileManager.default.removeItem(at: folder)
    fail("xcresulttool couldn't export attachments from \(options.path) (exit \(exportStatus))", status: 2)
}

let status: Int32
do {
    let reports = try ExportReader.reports(in: folder)
    print(options.json ? try SummaryFormatter.json(reports) : SummaryFormatter.text(reports), terminator: options.json ? "\n" : "")
    status = ExitPolicy.status(for: reports, failOn: options.failOn)
} catch EvalSummaryError.noEvaluations {
    try? FileManager.default.removeItem(at: folder)
    fail("No Siri evaluation results found in \(options.path)", status: 2)
} catch EvalSummaryError.malformed(let file) {
    try? FileManager.default.removeItem(at: folder)
    fail("Couldn't read evaluation result \(file)", status: 2)
} catch {
    try? FileManager.default.removeItem(at: folder)
    fail("Couldn't write the summary: \(error)", status: 2)
}
try? FileManager.default.removeItem(at: folder)
exit(status)
#else
fatalError("siri-ai-eval runs on macOS")
#endif
