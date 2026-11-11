import Testing
@testable import SiriAIKit

struct EvalSwitchTests {
    static let badHost: EvalSwitch = "bad-host"

    @Test func launchArgumentCarriesTheName() {
        #expect(Self.badHost.launchArgument == "--siri-ai-eval-switch=bad-host")
    }

    @Test(arguments: [
        ([String](), false),
        (["/path/to/App"], false),
        (["/path/to/App", "--siri-ai-eval-switch=bad-host"], true),
        (["/path/to/App", "--siri-ai-eval-switch=bad-host-later"], false),
        (["/path/to/App", "--siri-ai-eval-switch=tool-off-later"], false),
        (["/path/to/App", "bad-host"], false),
        (["/path/to/App", "-siri-ai-eval-switch=bad-host"], false),
    ])
    func isOnOnlyForItsOwnArgument(arguments: [String], expected: Bool) {
        #expect(Self.badHost.isOn(in: arguments) == expected)
    }

    @Test func launchArgumentRoundTrips() {
        let switches: [EvalSwitch] = ["bad-host", "cache-off", "api-500"]
        let arguments = switches.map(\.launchArgument)
        #expect(switches.allSatisfy { $0.isOn(in: arguments) })
        #expect(!EvalSwitch("tool-off").isOn(in: arguments))
    }

    @Test(arguments: [
        ("bad-host", true),
        ("api-500", true),
        ("x", true),
        ("", false),
        ("Bad-Host", false),
        ("bad host", false),
        ("bad=host", false),
        ("-bad", false),
        ("bad-", false),
    ])
    func validNames(name: String, expected: Bool) {
        #expect(EvalSwitch.isValidName(name) == expected)
    }
}
