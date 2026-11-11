import SiriAIKit
import SwiftUI

struct ContentView: View {
    @State private var orderProbe = "Indexing order probe…"

    var body: some View {
        VStack(spacing: 16) {
            Text("Ready")
                .accessibilityIdentifier("app-status")
            ToolOutcomeView()
            Text(orderProbe)
                .font(.caption)
                .accessibilityIdentifier(OrderProbe.accessibilityIdentifier)
            Text("Ask Siri: “In \(DemoAPI.appName), what's in my cart?”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task {
            orderProbe = await OrderProbe.run()
        }
    }
}
