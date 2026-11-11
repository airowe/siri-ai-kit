import Testing
@testable import SiriAIKit

struct EvalSwitchTests {
    static let refreshOff: EvalSwitch = "refresh-off"

    @Test func launchArgumentCarriesTheName() {
        #expect(Self.refreshOff.launchArgument == "--siri-ai-eval-switch=refresh-off")
    }

    @Test(arguments: [
        ([String](), false),
        (["/path/to/App"], false),
        (["/path/to/App", "--siri-ai-eval-switch=refresh-off"], true),
        (["/path/to/App", "--siri-ai-eval-switch=refresh-off-later"], false),
        (["/path/to/App", "--siri-ai-eval-switch=signed-out"], false),
        (["/path/to/App", "refresh-off"], false),
        (["/path/to/App", "-siri-ai-eval-switch=refresh-off"], false),
    ])
    func isOnOnlyForItsOwnArgument(arguments: [String], expected: Bool) {
        #expect(Self.refreshOff.isOn(in: arguments) == expected)
    }

    @Test func launchArgumentRoundTrips() {
        let switches: [EvalSwitch] = ["refresh-off", "signed-out", "api-500"]
        let arguments = switches.map(\.launchArgument)
        #expect(switches.allSatisfy { $0.isOn(in: arguments) })
        #expect(!EvalSwitch("tool-off").isOn(in: arguments))
    }

    @Test(arguments: [
        ("refresh-off", true),
        ("api-500", true),
        ("x", true),
        ("", false),
        ("Refresh-Off", false),
        ("refresh off", false),
        ("refresh=off", false),
        ("-refresh", false),
        ("refresh-", false),
    ])
    func validNames(name: String, expected: Bool) {
        #expect(EvalSwitch.isValidName(name) == expected)
    }
}
