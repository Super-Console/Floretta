import SwiftUI

// Blank system window shared by both app targets. No custom-drawn controls (TASKBOOK §1.1).
struct ContentView: View {
    var body: some View {
        #if os(macOS)
        Color.clear
            .frame(minWidth: 800, minHeight: 600)
        #else
        Color.clear
        #endif
    }
}
