import Testing
@testable import SyrupAIEvalSummary

struct EvaluationKindTests {
    static let name = "Cart contents, repeated"

    @Test(arguments: [
        (EvaluationKind.required, "Cart contents, repeated"),
        (.informational, "Cart contents, repeated [informational]"),
        (.negativeControl, "Cart contents, repeated [negative control]"),
    ])
    func tagAppendsTheKind(kind: EvaluationKind, expected: String) {
        #expect(kind.tag(Self.name) == expected)
    }

    @Test(arguments: EvaluationKind.allCases)
    func tagRoundTrips(kind: EvaluationKind) {
        #expect(EvaluationKind(evaluationName: kind.tag(Self.name)) == kind)
    }

    @Test(arguments: EvaluationKind.allCases)
    func taggingTwiceAddsOneTag(kind: EvaluationKind) {
        #expect(kind.tag(kind.tag(Self.name)) == kind.tag(Self.name))
    }

    @Test(arguments: [
        "Cart contents, repeated",
        "Cart [informational] contents",
        "Cart contents [Informational]",
        "",
    ])
    func untaggedNamesAreRequired(name: String) {
        #expect(EvaluationKind(evaluationName: name) == .required)
    }

    @Test func reportTakesItsKindFromItsName() {
        let report = EvalReport(name: EvaluationKind.negativeControl.tag(Self.name), runs: [])
        #expect(report.kind == .negativeControl)
        #expect(EvalReport(name: Self.name, runs: []).kind == .required)
    }
}
