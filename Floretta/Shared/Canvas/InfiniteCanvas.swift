import SwiftUI

struct InfiniteCanvas: View {
    @Binding var document: MindMapDocument

    @State private var viewport = CanvasViewport()
    @State private var drag: RootDrag?
    @State private var panAnchor: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var interaction = CanvasInteraction.standard
    @State private var chrome = CanvasChrome.standard
    @Binding var keyboard: MindMapKeyboardSession
    var focusNodeID: UUID? = nil
    var zenActive: Bool = false
    var onEscape: () -> Bool = { false }
    var onConsumeBlankDoubleTap: () -> Bool = { false }
    @State private var compositionWidth: CGFloat = 0
    @FocusState private var canvasFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(.background)
                    .contentShape(Rectangle())
                Canvas { context, size in
                    draw(in: context, size: size)
                }
                .allowsHitTesting(false)
            }
            .gesture(dragGesture)
            .simultaneousGesture(pinchGesture(in: geo.size))
            .overlay {
                CanvasScrollCatcher { delta, location, command in
                    viewport.applyScroll(delta: delta, around: location, command: command)
                    chrome.syncZoomPercent(toScale: viewport.scale)
                }
            }
            .overlay { if !zenActive { hoverAddButtons } }
            .overlay { editField }
            .canvasHover { location in
                guard let location else {
                    interaction.hoveredNodeID = nil
                    return
                }
                let point = viewport.canvasPoint(fromView: location)
                interaction.hoveredNodeID = CanvasPlacement.nodeID(at: point, in: layoutSource())
            }
            .focusable()
            .focusEffectDisabled()
            .focused($canvasFocused)
            .onKeyPress { press in
                if press.key == .escape, !keyboard.isComposing, onEscape() {
                    return .handled
                }
                guard keyboard.mode == .command else { return .ignored }
                guard let event = KeyEvent(press: press, mode: .command, isComposing: keyboard.isComposing) else {
                    return .ignored
                }
                return handleKey(event) ? .handled : .ignored
            }
            .onAppear {
                if keyboard.selectedNodeID == nil {
                    keyboard.selectedNodeID = document.roots.first?.id
                    interaction.selectedNodeID = keyboard.selectedNodeID
                }
                chrome.syncZoomPercent(toScale: viewport.scale)
                canvasFocused = true
            }
            .onChange(of: zoomPercent) { _, percent in
                chrome.zoomPercent = percent
            }
            .onChange(of: keyboard.mode) { _, mode in
                if mode == .command {
                    compositionWidth = 0
                    canvasFocused = true
                }
            }
            .onChange(of: keyboard.selectedNodeID) { _, id in
                interaction.selectedNodeID = id
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let point = viewport.canvasPoint(fromView: value.location)
                guard !keyboard.isComposing else { return }
                let hit = CanvasPlacement.nodeID(at: point, in: layoutSource())
                if zenActive, hit == nil { return }
                if keyboard.mode == .edit {
                    keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                }
                keyboard.selectedNodeID = hit
                interaction.selectedNodeID = hit
            })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                let point = viewport.canvasPoint(fromView: value.location)
                guard !keyboard.isComposing else { return }
                guard CanvasPlacement.nodeID(at: point, in: layoutSource()) == nil else { return }
                if onConsumeBlankDoubleTap() { return }
                if focusNodeID != nil { return }
                if keyboard.mode == .edit {
                    keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                }
                if let id = CanvasCommands.apply(
                    .addFloatingTopic(at: point),
                    document: &document,
                    interaction: &interaction
                ) {
                    keyboard.selectedNodeID = id
                    interaction.selectedNodeID = id
                }
            })
            .toolbar {
                if !zenActive {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            stepZoom(-1, around: center(of: geo.size))
                        } label: {
                            Label("Zoom Out", systemImage: "minus.magnifyingglass")
                        }
                        Button("\(zoomPercent)%") {
                            let anchor = center(of: geo.size)
                            viewport.zoom(to: ZoomStop.oneHundred.scale, around: anchor)
                            chrome.syncZoomPercent(toScale: viewport.scale)
                        }
                        .disabled(!chrome.zoomIsClickable)
                        Button {
                            stepZoom(1, around: center(of: geo.size))
                        } label: {
                            Label("Zoom In", systemImage: "plus.magnifyingglass")
                        }
                        if chrome.fitControlVisible {
                            Button {
                                fit(in: geo.size)
                            } label: {
                                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            .keyboardShortcut("0", modifiers: .command)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !zenActive { sheetBar }
            }
        }
    }

    private var zoomPercent: Int {
        ZoomStop.displayPercent(forScale: viewport.scale)
    }

    private func stepZoom(_ direction: Int, around anchor: CGPoint) {
        let next = ZoomStop.nearest(to: viewport.scale).stepped(direction)
        viewport.zoom(to: next.scale, around: anchor)
        chrome.syncZoomPercent(toScale: viewport.scale)
    }

    private func layoutSource() -> MindMapDocument {
        FocusLayout.focusedDocument(document, focus: focusNodeID)
    }

    private var sheetBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(chrome.sheets.enumerated()), id: \.element.id) { index, sheet in
                Button(sheet.title) {
                    chrome.selectSheet(index)
                }
                .buttonStyle(.bordered)
            }
            Button("Add Page") {
                chrome.addSheet(title: "Page \(chrome.sheets.count + 1)")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var hoverAddButtons: some View {
        if let id = interaction.hoveredNodeID,
           let frame = placedFrames().first(where: { $0.id == id }) {
            let rect = viewport.viewRect(fromCanvas: frame.frame)
            addButton(.up, at: CGPoint(x: rect.midX, y: rect.minY - 18), parent: id)
            addButton(.down, at: CGPoint(x: rect.midX, y: rect.maxY + 18), parent: id)
            addButton(.left, at: CGPoint(x: rect.minX - 18, y: rect.midY), parent: id)
            addButton(.right, at: CGPoint(x: rect.maxX + 18, y: rect.midY), parent: id)
        }
    }

    @ViewBuilder
    private var editField: some View {
        if keyboard.mode == .edit,
           let id = keyboard.selectedNodeID,
           let frame = placedFrames().first(where: { $0.id == id }) {
            let rect = viewport.viewRect(fromCanvas: frame.frame)
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: frame.fontSize * max(viewport.scale, 1),
                onEvent: { handleKey($0) }
            )
            .frame(width: max(rect.width, compositionWidth, 88), height: max(rect.height, 36))
            .position(x: rect.midX, y: rect.midY)
        }
    }

    private func placedFrames() -> [NodeFrame] {
        CanvasPlacement.nodes(in: layoutSource())
    }

    @discardableResult
    private func handleKey(_ event: KeyEvent) -> Bool {
        if event.key == .escape, event.modifiers.isEmpty, !event.isComposing, !keyboard.isComposing, onEscape() {
            return true
        }
        let command = keyboard.handle(event, document: &document, frames: placedFrames())
        interaction.selectedNodeID = keyboard.selectedNodeID
        return command != nil
    }

    private func addButton(_ direction: CanvasDirection, at point: CGPoint, parent: UUID) -> some View {
        Button {
            _ = CanvasCommands.apply(
                .addChild(parentID: parent, direction: direction),
                document: &document,
                interaction: &interaction
            )
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        .position(point)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag == nil && panAnchor == nil {
                    let start = viewport.canvasPoint(fromView: value.startLocation)
                    if let id = CanvasPlacement.rootID(at: start, in: layoutSource()),
                       document.parentID(of: id) == nil,
                       let frame = placedFrames().first(where: { $0.id == id })?.frame {
                        drag = RootDrag(
                            id: id,
                            grabX: start.x - frame.minX,
                            grabY: start.y - frame.minY
                        )
                    } else {
                        panAnchor = viewport.offset
                    }
                }
                if let drag {
                    let point = viewport.canvasPoint(fromView: value.location)
                    let origin = CGPoint(x: point.x - drag.grabX, y: point.y - drag.grabY)
                    document = CanvasPlacement.movingRoot(drag.id, to: origin, in: document)
                } else if let panAnchor {
                    viewport.offset = CGPoint(
                        x: panAnchor.x + value.translation.width,
                        y: panAnchor.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                drag = nil
                panAnchor = nil
            }
    }

    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = viewport.scale
                }
                let start = pinchStartScale ?? viewport.scale
                viewport.zoom(to: start * value.magnification, around: center(of: size))
                chrome.syncZoomPercent(toScale: viewport.scale)
            }
            .onEnded { _ in
                pinchStartScale = nil
                viewport.snapToStop(around: center(of: size))
                chrome.syncZoomPercent(toScale: viewport.scale)
            }
    }

    private func fit(in size: CGSize) {
        guard let bounds = CanvasPlacement.contentBounds(in: layoutSource()) else { return }
        viewport.fit(content: bounds, in: size)
        viewport.snapToStop(around: center(of: size))
        chrome.syncZoomPercent(toScale: viewport.scale)
    }

    private func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawGrid(in: context, size: size)
        let placed = placedFrames()
        for node in placed {
            guard let link = node.link else { continue }
            var curve = Path()
            curve.move(to: viewport.viewPoint(fromCanvas: link.start))
            curve.addCurve(
                to: viewport.viewPoint(fromCanvas: link.end),
                control1: viewport.viewPoint(fromCanvas: link.control1),
                control2: viewport.viewPoint(fromCanvas: link.control2)
            )
            context.stroke(
                curve,
                with: .color(color(link.color)),
                lineWidth: link.lineWidth
            )
        }
        for node in placed {
            let rect = viewport.viewRect(fromCanvas: node.frame)
            let path = Path(roundedRect: rect, cornerRadius: node.cornerRadius)
            if !node.hidesFill {
                context.fill(path, with: .color(color(node.fill)))
            }
            let selected = interaction.selectedNodeID == node.id
            let border = selected ? interaction.selectionBorder : node.border
            let width = selected ? interaction.selectionBorderWidth : node.borderWidth
            if width > 0 {
                context.stroke(path, with: .color(color(border)), lineWidth: width)
            }
            if selected && interaction.showsSelectionChrome {
                drawHandles(around: rect, in: context)
            }
            context.draw(
                styledText(node),
                in: rect.insetBy(dx: 10, dy: 6)
            )
        }
    }

    private func drawHandles(around rect: CGRect, in context: GraphicsContext) {
        let handle: CGFloat = 6
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        for point in points {
            let mark = CGRect(x: point.x - handle / 2, y: point.y - handle / 2, width: handle, height: handle)
            context.fill(Path(mark), with: .color(color(interaction.selectionBorder)))
        }
    }

    private func styledText(_ node: NodeFrame) -> Text {
        var text = Text(node.text)
            .font(.system(size: node.fontSize, design: fontDesign(node.fontDesign)))
            .foregroundStyle(color(node.textColor))
        if node.bold { text = text.bold() }
        if node.italic { text = text.italic() }
        if node.strikethrough { text = text.strikethrough() }
        if node.underline { text = text.underline() }
        return text
    }

    private func fontDesign(_ name: String) -> Font.Design {
        switch name {
        case "serif": return .serif
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        default: return .default
        }
    }

    private func color(_ value: BranchColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        let step = max(18, 32 * viewport.scale)
        guard step.isFinite, size.width > 0, size.height > 0 else { return }
        var x = viewport.offset.x.truncatingRemainder(dividingBy: step)
        if x < 0 { x += step }
        var drawn = 0
        while x < size.width && drawn < 800 {
            var y = viewport.offset.y.truncatingRemainder(dividingBy: step)
            if y < 0 { y += step }
            while y < size.height && drawn < 800 {
                let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                context.fill(dot, with: .color(.secondary.opacity(0.35)))
                y += step
                drawn += 1
            }
            x += step
        }
    }

}

private struct RootDrag {
    var id: UUID
    var grabX: CGFloat
    var grabY: CGFloat
}

private extension View {
    @ViewBuilder
    func canvasHover(_ update: @escaping (CGPoint?) -> Void) -> some View {
        #if os(macOS)
        onContinuousHover { phase in
            switch phase {
            case .active(let location):
                update(location)
            case .ended:
                update(nil)
            }
        }
        #else
        self
        #endif
    }
}
