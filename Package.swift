// swift-tools-version: 6.2
import PackageDescription

let evaluationFrameworks: [LinkerSetting] = ["XCTest", "SiriEvaluations", "Evaluations", "AppIntentsTesting"]
    .map { .linkedFramework($0, .when(platforms: [.iOS])) }

let package = Package(
    name: "SyrupAIKit",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "SyrupAIKit", targets: ["SyrupAIKit"]),
        .library(name: "SyrupAIEvalKit", targets: ["SyrupAIEvalKit"]),
        .executable(name: "syrup-ai-eval", targets: ["syrup-ai-eval"]),
    ],
    targets: [
        .target(name: "SyrupAIKit"),
        .target(name: "SyrupAIEvalKit", dependencies: ["SyrupAIKit", "SyrupAIEvalSummary"], linkerSettings: evaluationFrameworks),
        .target(name: "SyrupAIEvalSummary"),
        .executableTarget(name: "syrup-ai-eval", dependencies: ["SyrupAIEvalSummary"]),
        .testTarget(name: "SyrupAIKitTests", dependencies: ["SyrupAIKit"]),
        .testTarget(name: "SyrupAIEvalKitTests", dependencies: ["SyrupAIEvalKit"]),
        .testTarget(name: "SyrupAIEvalSummaryTests", dependencies: ["SyrupAIEvalSummary"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
