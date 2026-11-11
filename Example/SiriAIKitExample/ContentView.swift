import SiriAIKit
import SwiftUI

struct ContentView: View {
    @State private var status = "Signing in…"
    @State private var orderProbe = "Indexing order probe…"

    var body: some View {
        VStack(spacing: 16) {
            Text(status)
                .accessibilityIdentifier("auth-status")
            HStack {
                Button("Sign in again") { Task { await signIn() } }
                Button("Sign out") {
                    DemoAPI.signOut()
                    status = "Signed out"
                }
            }
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
            await signIn()
            orderProbe = await OrderProbe.run()
        }
    }

    private func signIn() async {
        do {
            try await DemoAPI.signIn()
            status = "Signed in at \(Date.now.formatted(date: .omitted, time: .standard))"
        } catch {
            status = "Sign-in failed: \(error)"
        }
    }
}
