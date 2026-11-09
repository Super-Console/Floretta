import SwiftUI

struct InfiniteCanvas: View {
    @Binding var document: MindMapDocument

    @State private var viewport = CanvasViewport()
    @State private var drag: RootDrag?
    @State private var panAnchor: CGPoint?
    @State private var pinchStartScale: CGFloat?

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
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewport.zoom(by: 1 / 1.1, around: center(of: geo.size))
                    } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    Button {
                        viewport.zoom(by: 1.1, around: center(of: geo.size))
                    } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag == nil && panAnchor == nil {
                    let start = viewport.canvasPoint(fromView: value.startLocation)
                    if let id = CanvasPlacement.rootID(at: start, in: document),
                       let frame = CanvasPlacement.nodes(in: document).first(where: { $0.id == id })?.frame {
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
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private func fit(in size: CGSize) {
        guard let bounds = CanvasPlacement.contentBounds(in: document) else { return }
        viewport.fit(content: bounds, in: size)
    }

    private func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawGrid(in: context, size: size)
        let placed = CanvasPlacement.nodes(in: document)
        var byID: [UUID: PlacedNode] = [:]
        for node in placed {
            byID[node.id] = node
        }
        for node in placed {
            guard let parentID = node.parentID, let parent = byID[parentID] else { continue }
            let start = viewport.viewPoint(fromCanvas: center(of: parent.frame))
            let end = viewport.viewPoint(fromCanvas: center(of: node.frame))
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
        }
        for node in placed {
            let rect = viewport.viewRect(fromCanvas: node.frame)
            let path = Path(roundedRect: rect, cornerRadius: 8)
            context.fill(
                path,
                with: .color(Color.primary.opacity(node.isRoot ? 0.08 : 0.04))
            )
            context.stroke(
                path,
                with: .color(Color.primary.opacity(node.isRoot ? 0.7 : 0.35)),
                lineWidth: node.isRoot ? 1.5 : 1
            )
            context.draw(
                Text(node.text).font(.body),
                in: rect.insetBy(dx: 10, dy: 6)
            )
        }
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

    private func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }
}

private struct RootDrag {
    var id: UUID
    var grabX: CGFloat
    var grabY: CGFloat
}
