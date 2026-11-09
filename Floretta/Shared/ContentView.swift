import SwiftUI

// Blank window plus a system alert when an autosave copy is waiting.
// No custom-drawn controls (TASKBOOK §1.1).
struct ContentView: View {
    @Bindable var recovery: RecoveryPresenter

    var body: some View {
        root
            .alert("Recover unsaved mind map?", isPresented: $recovery.showOffer) {
                Button("Recover") { recovery.restore() }
                Button("Discard", role: .destructive) { recovery.discard() }
            } message: {
                Text(recovery.offerMessage)
            }
            .alert("Couldn't recover autosave", isPresented: $recovery.showFailure) {
                Button("OK", role: .cancel) { recovery.acknowledgeFailure() }
            } message: {
                Text(recovery.failureMessage)
            }
            .onAppear { recovery.checkOnLaunch() }
    }

    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        Color.clear
            .frame(minWidth: 800, minHeight: 600)
        #else
        Color.clear
        #endif
    }
}
