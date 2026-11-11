import SiriAIKit
import SwiftUI

@main
struct SiriAIKitExampleApp: App {
    init() {
        #if DEBUG
        KeychainLockCheck.warnIfLockedOut(service: DemoAPI.keychainService)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
