import SwiftUI

// Shared entry point. Floretta-macOS and Floretta-iOS each compile this file.
@main
struct FlorettaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
    }
}
