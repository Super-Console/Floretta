import SwiftUI

struct ContentView: View {
    @Bindable var recovery: RecoveryPresenter
    @State private var document = openingMap()
    @State private var keyboard = MindMapKeyboardSession()

    var body: some View {
        NavigationSplitView {
            OutlineView(document: $document, keyboard: $keyboard)
        } detail: {
            canvas
        }
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
            .onChange(of: recovery.restoredDocument) { _, restored in
                if let restored {
                    document = restored
                    keyboard = MindMapKeyboardSession()
                    keyboard.selectedNodeID = document.roots.first?.id
                }
            }
            .onAppear {
                if keyboard.selectedNodeID == nil {
                    keyboard.selectedNodeID = document.roots.first?.id
                }
            }
            .onChange(of: document) { _, updated in
                recovery.noteEdit(updated)
            }
    }

    @ViewBuilder
    private var canvas: some View {
        #if os(macOS)
        InfiniteCanvas(document: $document, keyboard: $keyboard)
            .frame(minWidth: 800, minHeight: 600)
        #else
        InfiniteCanvas(document: $document, keyboard: $keyboard)
        #endif
    }
}

/// Opening map so the canvas is not empty before New/Open exists.
/// Positions are unset until a root is dragged.
private func openingMap() -> MindMapDocument {
    let child = MindMapNode(id: stableID("22222222-2222-2222-2222-222222222222"), text: "子节点")
    let center = MindMapNode(
        id: stableID("11111111-1111-1111-1111-111111111111"),
        text: "中心",
        children: [child]
    )
    let floating = MindMapNode(id: stableID("33333333-3333-3333-3333-333333333333"), text: "浮动")
    return MindMapDocument(title: "未命名", roots: [center, floating])
}

private func stableID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}
