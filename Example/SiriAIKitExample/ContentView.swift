import SiriAIKit
import SwiftUI

struct ContentView: View {
    @State private var status = "Signing in…"

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
            Text("Ask Siri: “In \(DemoAPI.appName), what's in my cart?”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task { await signIn() }
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
