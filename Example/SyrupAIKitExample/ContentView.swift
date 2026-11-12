import SyrupAIKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Ready")
                .accessibilityIdentifier("app-status")
#if DEBUG
            ToolOutcomeView()
#endif
            Text("Ask Siri: “In \(DemoAPI.appName), what's in my cart?”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
