// swift-tools-version: 6.2
import PackageDescription

let evaluationFrameworks: [LinkerSetting] = ["XCTest", "SiriEvaluations", "Evaluations", "AppIntentsTesting"]
    .map { .linkedFramework($0, .when(platforms: [.iOS])) }

let package = Package(
    name: "SiriAIKit",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "SiriAIKit", targets: ["SiriAIKit"]),
        .library(name: "SiriAIEvalKit", targets: ["SiriAIEvalKit"]),
        .executable(name: "siri-ai-eval", targets: ["siri-ai-eval"]),
    ],
    targets: [
        .target(name: "SiriAIKit"),
        .target(name: "SiriAIEvalKit", dependencies: ["SiriAIKit", "SiriAIEvalSummary"], linkerSettings: evaluationFrameworks),
        .target(name: "SiriAIEvalSummary"),
        .executableTarget(name: "siri-ai-eval", dependencies: ["SiriAIEvalSummary"]),
        .testTarget(name: "SiriAIKitTests", dependencies: ["SiriAIKit"]),
        .testTarget(name: "SiriAIEvalSummaryTests", dependencies: ["SiriAIEvalSummary"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
