import FlorettaCore
import SwiftUI

/// The same `MindMapDocument` as the canvas, drawn with system list controls.
struct OutlineView: View {
    @Binding var document: MindMapDocument
    @Binding var keyboard: MindMapKeyboardSession
    var tagFilter: TopicTagFilter = TopicTagFilter()
    /// Markdown mode has no collapse control. The tree stays expanded.
    var locksCollapse: Bool = false
    var onChromeCommand: (MindMapCommand) -> Void = { _ in }
    @State private var keyCoalescer = KeyDeliveryCoalescer()
    #if os(iOS)
    @State private var reorderMode: EditMode = .inactive
    #endif
    @FocusState private var outlineFocused: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        #if os(iOS)
        keyedList
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(reorderMode == .active ? text("完成") : text("排序")) {
                        reorderMode = reorderMode == .active ? .inactive : .active
                    }
                }
            }
        #else
        keyedList
        #endif
    }

    private var keyedList: some View {
        outlineList
            .navigationTitle(text("大纲"))
            .focusable()
            .focused($outlineFocused)
            .onKeyPress { press in
                guard keyboard.mode == .command else { return .ignored }
                guard let event = KeyEvent(press: press, mode: .command, isComposing: keyboard.isComposing) else {
                    return .ignored
                }
                let handled = MindMapKeyDispatch.handle(
                    event,
                    keyboard: &keyboard,
                    document: &document,
                    frames: [],
                    surface: .outline,
                    coalescer: keyCoalescer,
                    onChrome: onChromeCommand
                )
                return handled ? .handled : .ignored
            }
    }

    private var outlineList: some View {
        let list = List(selection: selection) {
            OutlineLevel(
                document: $document,
                keyboard: $keyboard,
                tagFilter: tagFilter,
                parentID: nil,
                locksCollapse: locksCollapse
            )
            if !document.freeNodes.isEmpty {
                Section(text("自由节点")) {
                    ForEach(document.freeNodes.map(\.id), id: \.self) { id in
                        OutlineRow(document: $document, keyboard: $keyboard, tagFilter: tagFilter, id: id)
                            .tag(id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        return list.environment(\.editMode, $reorderMode)
        #else
        return list
        #endif
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { keyboard.selectedNodeID },
            set: { keyboard.selectedNodeID = $0 }
        )
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }
}

/// One level of sibling ids. Child levels are separate views, so expanding one
/// row does not rebuild the other branches.
private struct OutlineLevel: View {
    @Binding var document: MindMapDocument
    @Binding var keyboard: MindMapKeyboardSession
    var tagFilter: TopicTagFilter
    var parentID: UUID?
    var locksCollapse: Bool

    var body: some View {
        let ids = childIDs
        ForEach(ids, id: \.self) { id in
            if locksCollapse {
                OutlineRow(document: $document, keyboard: $keyboard, tagFilter: tagFilter, id: id)
                    .tag(id)
                    .draggable(id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                        let count = document.node(id)?.children.count ?? 0
                        return keyboard.reparentNode(dragged, to: id, at: count, document: &document)
                    }
                OutlineLevel(
                    document: $document,
                    keyboard: $keyboard,
                    tagFilter: tagFilter,
                    parentID: id,
                    locksCollapse: true
                )
            } else {
                DisclosureGroup(isExpanded: expanded(id)) {
                    if document.node(id)?.isCollapsed == false {
                        OutlineLevel(
                            document: $document,
                            keyboard: $keyboard,
                            tagFilter: tagFilter,
                            parentID: id,
                            locksCollapse: false
                        )
                    }
                } label: {
                    OutlineRow(document: $document, keyboard: $keyboard, tagFilter: tagFilter, id: id)
                }
                .tag(id)
                .draggable(id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                    let count = document.node(id)?.children.count ?? 0
                    return keyboard.reparentNode(dragged, to: id, at: count, document: &document)
                }
            }
        }
        .onMove { source, destination in
            keyboard.reorderChildren(of: parentID, from: source, to: destination, document: &document)
        }
    }

    private var childIDs: [UUID] {
        if let parentID {
            return document.node(parentID)?.children.map(\.id) ?? []
        }
        return document.roots.map(\.id)
    }

    private func expanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { document.node(id)?.isCollapsed == false },
            set: { keyboard.setCollapsed(!$0, nodeID: id, document: &document) }
        )
    }
}

private struct OutlineRow: View {
    @Binding var document: MindMapDocument
    @Binding var keyboard: MindMapKeyboardSession
    var tagFilter: TopicTagFilter
    var id: UUID
    @State private var minimumWidth: CGFloat = 0
    @Environment(\.appearanceProfile) private var appearanceProfile

    var body: some View {
        if keyboard.mode == .edit, keyboard.selectedNodeID == id {
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $minimumWidth,
                fontSize: 17,
                onEvent: { event in
                    keyboard.handle(event, document: &document, frames: [], surface: .outline) != nil
                }
            )
            .frame(minWidth: max(minimumWidth, 80), minHeight: 28)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.node(id)?.text ?? "")
                    .font(FlorettaTitleFont.font(design: "default", size: 17, familyID: appearanceProfile.fontFamilyID))
                    .lineLimit(3)
                if let labels = document.node(id)?.labels, !labels.isEmpty {
                    Text(verbatim: labels.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let label = document.node(id)?.attachmentSizeLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .opacity(rowOpacity)
        }
    }

    private var rowOpacity: Double {
        guard tagFilter.isActive, let node = document.node(id) else { return 1 }
        if tagFilter.matches(node) || keyboard.selectedNodeID == id { return 1 }
        return TopicTagCanvas.dimOpacity
    }
}
