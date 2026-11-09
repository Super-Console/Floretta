import FlorettaCore
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct InfiniteCanvas: View {
    @Binding var document: MindMapDocument

    @State private var drag: RootDrag?
    @State private var panAnchor: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var interaction = CanvasInteraction.standard
    @Binding var keyboard: MindMapKeyboardSession
    var camera: CanvasCamera
    var focusNodeID: UUID? = nil
    var zenActive: Bool = false
    var onEscape: () -> Bool = { false }
    var onConsumeBlankDoubleTap: () -> Bool = { false }
    var thumbnails: AttachmentThumbnailMemory? = nil
    var thumbnailCache: ThumbnailFileCache? = nil
    var attachmentArchive: URL? = nil
    var spillDirectory: URL? = nil
    var attachmentEntries: [ZipStoredEntry] = []
    @State private var compositionWidth: CGFloat = 0
    @State private var dotTiles = DotTileCache()
    @State private var laidOut = LaidOutFrames()
    @Environment(\.colorScheme) private var colorScheme
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
                    camera.viewport.applyScroll(delta: delta, around: location, command: command)
                    camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
                }
            }
            .overlay { if !zenActive { hoverAddButtons } }
            .overlay { editField }
            .canvasHover { location in
                guard let location else {
                    interaction.hoveredNodeID = nil
                    return
                }
                let point = camera.viewport.canvasPoint(fromView: location)
                interaction.hoveredNodeID = CanvasPlacement.nodeID(at: point, in: layoutSource())
            }
            .focusable(keyboard.mode == .command)
            .focusEffectDisabled(true)
            .background { CanvasFocusRingSuppressor() }
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
                camera.viewSize = geo.size
                publishBounds()
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
                refreshThumbnails()
                canvasFocused = true
            }
            .onChange(of: geo.size) { _, size in
                camera.viewSize = size
                refreshThumbnails()
            }
            .onChange(of: document) { _, _ in
                publishBounds()
                refreshThumbnails()
            }
            .onChange(of: focusNodeID) { _, _ in
                publishBounds()
            }
            .onChange(of: camera.viewport.scale) { _, scale in
                camera.chrome.syncZoomPercent(toScale: scale)
                refreshThumbnails()
            }
            .onChange(of: camera.viewport.offset) { _, _ in
                refreshThumbnails()
            }
            .onChange(of: keyboard.mode) { _, mode in
                if mode == .command {
                    compositionWidth = 0
                    canvasFocused = true
                } else {
                    canvasFocused = false
                }
            }
            .onChange(of: keyboard.selectedNodeID) { _, id in
                interaction.selectedNodeID = id
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if EditFieldGuard.ignoresCanvasTap(
                    at: value.location,
                    editFrame: editFieldFrame(),
                    isComposing: keyboard.isComposing
                ) { return }
                let point = camera.viewport.canvasPoint(fromView: value.location)
                let hit = CanvasPlacement.nodeID(at: point, in: layoutSource())
                if zenActive, hit == nil { return }
                applyNodeTap(hit)
            })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                if EditFieldGuard.ignoresCanvasTap(
                    at: value.location,
                    editFrame: editFieldFrame(),
                    isComposing: keyboard.isComposing
                ) { return }
                let point = camera.viewport.canvasPoint(fromView: value.location)
                if let hit = CanvasPlacement.nodeID(at: point, in: layoutSource()) {
                    beginEditing(hit)
                    return
                }
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
        }
        .focusEffectDisabled(true)
    }

    private func applyNodeTap(_ hit: UUID?) {
        switch NodeEditTap.action(
            hit: hit,
            selected: keyboard.selectedNodeID,
            mode: keyboard.mode,
            isComposing: keyboard.isComposing
        ) {
        case .ignore:
            return
        case .select(let id):
            keyboard.selectedNodeID = id
            interaction.selectedNodeID = id
        case .beginEdit(let id):
            beginEditing(id)
        case .commitAndSelect(let id):
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedNodeID = id
            interaction.selectedNodeID = id
            canvasFocused = true
        }
    }

    private func beginEditing(_ id: UUID) {
        keyboard.selectedNodeID = id
        interaction.selectedNodeID = id
        canvasFocused = false
        guard keyboard.mode != .edit else { return }
        keyboard.apply(.beginEdit, document: &document, frames: placedFrames())
    }

    private func layoutSource() -> MindMapDocument {
        FocusLayout.focusedDocument(document, focus: focusNodeID)
    }

    private func publishBounds() {
        camera.contentBounds = CanvasPlacement.contentBounds(in: layoutSource())
    }

    @ViewBuilder
    private var hoverAddButtons: some View {
        if let id = interaction.hoveredNodeID,
           let frame = placedFrames().first(where: { $0.id == id }) {
            let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
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
            let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(
                    fontSize: frame.fontSize,
                    scale: camera.viewport.scale
                ),
                onEvent: { handleKey($0) }
            )
            .frame(width: max(rect.width, compositionWidth, 88), height: max(rect.height, 36))
            .position(x: rect.midX, y: rect.midY)
        }
    }

    /// View rect of the system text field, including the extra width used while
    /// marked text is wider than the topic.
    private func editFieldFrame() -> CGRect? {
        guard keyboard.mode == .edit,
              let id = keyboard.selectedNodeID,
              let frame = placedFrames().first(where: { $0.id == id }) else { return nil }
        let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
        let width = max(rect.width, compositionWidth, 88)
        let height = max(rect.height, 36)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private func placedFrames() -> [NodeFrame] {
        laidOut.frames(for: layoutSource())
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
                    let start = camera.viewport.canvasPoint(fromView: value.startLocation)
                    if let id = CanvasPlacement.rootID(at: start, in: layoutSource()),
                       document.parentID(of: id) == nil,
                       let frame = placedFrames().first(where: { $0.id == id })?.frame {
                        drag = RootDrag(
                            id: id,
                            grabX: start.x - frame.minX,
                            grabY: start.y - frame.minY
                        )
                    } else {
                        panAnchor = camera.viewport.offset
                    }
                }
                if let drag {
                    let point = camera.viewport.canvasPoint(fromView: value.location)
                    let origin = CGPoint(x: point.x - drag.grabX, y: point.y - drag.grabY)
                    document = CanvasPlacement.movingRoot(drag.id, to: origin, in: document)
                } else if let panAnchor {
                    camera.viewport.offset = CGPoint(
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
                    pinchStartScale = camera.viewport.scale
                }
                let start = pinchStartScale ?? camera.viewport.scale
                camera.viewport.zoom(to: start * value.magnification, around: center(of: size))
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            }
            .onEnded { _ in
                pinchStartScale = nil
                camera.viewport.snapToStop(around: center(of: size))
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            }
    }

    private func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawGrid(in: context, size: size)
        let placed = placedFrames()
        let viewport = camera.viewport.canvasRect(in: size).insetBy(dx: -48, dy: -48)
        let visible = CanvasPlacement.frames(placed, intersectingCanvas: viewport)
        let linkIDs = CanvasPlacement.nodeIDsWithVisibleLinks(placed, viewport: viewport)
        let scale = camera.viewport.scale
        for node in placed where linkIDs.contains(node.id) {
            guard let link = node.link else { continue }
            stroke(
                link,
                straight: CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                in: context
            )
        }
        for node in visible {
            let onScreen = min(node.size.width, node.size.height) * scale
            draw(node, detail: CanvasDetail.level(scale: scale, onScreenHeight: onScreen), scale: scale, in: context)
        }
    }

    private func stroke(_ link: LinkCurve, straight: Bool, in context: GraphicsContext) {
        var path = Path()
        let start = camera.viewport.viewPoint(fromCanvas: link.start)
        let end = camera.viewport.viewPoint(fromCanvas: link.end)
        path.move(to: start)
        if straight {
            path.addLine(to: end)
        } else {
            path.addCurve(
                to: end,
                control1: camera.viewport.viewPoint(fromCanvas: link.control1),
                control2: camera.viewport.viewPoint(fromCanvas: link.control2)
            )
        }
        context.stroke(path, with: .color(color(link.color)), lineWidth: link.lineWidth)
    }

    private func draw(_ node: NodeFrame, detail: CanvasDetail, scale: CGFloat, in context: GraphicsContext) {
        let rect = camera.viewport.viewRect(fromCanvas: node.frame)
        let path = Path(roundedRect: rect, cornerRadius: detail == .far ? min(node.cornerRadius, 4) : node.cornerRadius)
        let selected = interaction.selectedNodeID == node.id
        if !node.hidesFill {
            if detail.drawsShadow {
                var shadowed = context
                shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5))
                shadowed.fill(path, with: .color(color(node.fill)))
            } else {
                context.fill(path, with: .color(color(node.fill)))
            }
        }
        if detail != .far, selected {
            context.stroke(
                path,
                with: .color(color(interaction.selectionBorder)),
                lineWidth: interaction.selectionBorderWidth
            )
        } else if detail.drawsFineBorder || (detail == .mid && node.borderWidth >= 2.5) {
            if node.borderWidth > 0 {
                context.stroke(path, with: .color(color(node.border)), lineWidth: node.borderWidth)
            }
        }
        if selected, detail.drawsSelectionHandles {
            drawHandles(around: rect, in: context)
        }
        var textRect = rect.insetBy(dx: 6, dy: 4)
        if detail != .far,
           let hash = node.thumbnailHashes.first,
           let image = thumbnails?.image(for: hash) {
            let imageRect = ImagePlacement.rect(for: image, in: rect)
            context.draw(Image(decorative: image, scale: 1), in: imageRect)
            textRect = CGRect(
                x: rect.minX + 6,
                y: imageRect.maxY + 2,
                width: max(0, rect.width - 12),
                height: max(0, rect.maxY - imageRect.maxY - 6)
            )
        }
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: node.fontSize, scale: scale)
        if CanvasTextLOD.level(onScreenPointSize: pointSize).drawsTitle, textRect.height > 1, textRect.width > 1 {
            let text = styledText(node, pointSize: pointSize)
            var layer = context
            layer.clip(to: Path(textRect))
            layer.draw(text, at: CGPoint(x: textRect.midX, y: textRect.midY), anchor: .center)
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

    private func refreshThumbnails() {
        let view = camera.viewport.canvasRect(in: camera.viewSize)
        let viewport = AttachmentViewportRect(
            minX: view.minX,
            minY: view.minY,
            maxX: view.maxX,
            maxY: view.maxY
        )
        let nodes = laidOut.frames(for: document).map { frame in
            (
                AttachmentViewportRect(
                    minX: frame.origin.x,
                    minY: frame.origin.y,
                    maxX: frame.origin.x + frame.size.width,
                    maxY: frame.origin.y + frame.size.height
                ),
                frame.thumbnailHashes
            )
        }
        let visible = ThumbnailResidence.visibleHashes(nodes: nodes, viewport: viewport)
        thumbnails?.sync(
            visible: visible,
            cache: thumbnailCache,
            archiveURL: attachmentArchive,
            spillDirectory: spillDirectory,
            entries: attachmentEntries
        )
    }

    private func styledText(_ node: NodeFrame, pointSize: CGFloat) -> Text {
        let shown = node.caption.isEmpty ? node.text : node.text + "\n" + node.caption
        var text = Text(shown)
            .font(.system(size: pointSize, design: fontDesign(node.fontDesign)))
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

    /// One pattern fill of a step×step dot tile. No per-dot loop and no count cap.
    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        guard let layout = DotLatticeLayout.make(
            offset: camera.viewport.offset,
            scale: camera.viewport.scale,
            viewSize: size
        ) else { return }
        let tile = dotTiles.image(step: layout.step, scheme: colorScheme)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .tiledImage(tile, origin: layout.tileOrigin, scale: 1)
        )
    }

}

/// Taps that land on the system text field must not commit or close it.
/// The field is at least 88 points wide, so a short Chinese topic leaves a
/// margin that the node hit-test misses. Marked text makes that margin larger.
enum EditFieldGuard {
    static func ignoresCanvasTap(at location: CGPoint, editFrame: CGRect?, isComposing: Bool) -> Bool {
        if isComposing { return true }
        guard let editFrame else { return false }
        return editFrame.contains(location)
    }
}

/// Touch editing. The first tap selects. The next tap on that node opens the
/// system text view and must not also close it, or typed characters never land.
enum NodeEditTap {
    enum Action: Equatable {
        case ignore
        case select(UUID?)
        case beginEdit(UUID)
        case commitAndSelect(UUID?)
    }

    static func action(
        hit: UUID?,
        selected: UUID?,
        mode: KeyboardMode,
        isComposing: Bool
    ) -> Action {
        if isComposing { return .ignore }
        if mode == .edit {
            if hit != nil, hit == selected { return .ignore }
            return .commitAndSelect(hit)
        }
        if let hit, hit == selected {
            return .beginEdit(hit)
        }
        return .select(hit)
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

/// World-locked dot lattice. One tile covers the viewport; spacing is `worldStep` canvas units.
struct DotLatticeLayout: Equatable {
    static let worldStep: CGFloat = 32

    var step: CGFloat
    /// Lattice point in view space, in `[0, step)`.
    var phase: CGPoint
    /// View-space top-left of the tile centered on `phase`.
    var tileOrigin: CGPoint
    /// Fill rect in the space whose origin is `tileOrigin`. Edges sit on tile boundaries.
    var fillRectInTileSpace: CGRect

    var fillRectInView: CGRect {
        fillRectInTileSpace.offsetBy(dx: tileOrigin.x, dy: tileOrigin.y)
    }

    static func make(offset: CGPoint, scale: CGFloat, viewSize: CGSize) -> DotLatticeLayout? {
        guard scale.isFinite, scale > 0,
              viewSize.width > 0, viewSize.height > 0,
              viewSize.width.isFinite, viewSize.height.isFinite else { return nil }
        let step = worldStep * scale
        guard step.isFinite, step >= 1 else { return nil }
        let phase = CGPoint(
            x: positiveRemainder(offset.x, modulo: step),
            y: positiveRemainder(offset.y, modulo: step)
        )
        let tileOrigin = CGPoint(x: phase.x - step / 2, y: phase.y - step / 2)
        let minX = -tileOrigin.x
        let minY = -tileOrigin.y
        let maxX = minX + viewSize.width
        let maxY = minY + viewSize.height
        let snappedMinX = floor((minX - step) / step) * step
        let snappedMinY = floor((minY - step) / step) * step
        let snappedMaxX = ceil((maxX + step) / step) * step
        let snappedMaxY = ceil((maxY + step) / step) * step
        return DotLatticeLayout(
            step: step,
            phase: phase,
            tileOrigin: tileOrigin,
            fillRectInTileSpace: CGRect(
                x: snappedMinX,
                y: snappedMinY,
                width: snappedMaxX - snappedMinX,
                height: snappedMaxY - snappedMinY
            )
        )
    }

    func coversView(_ viewSize: CGSize) -> Bool {
        let fill = fillRectInView
        return fill.minX <= 0 && fill.minY <= 0 && fill.maxX >= viewSize.width && fill.maxY >= viewSize.height
    }
}

func positiveRemainder(_ value: CGFloat, modulo step: CGFloat) -> CGFloat {
    guard step > 0, value.isFinite else { return 0 }
    let remainder = value.truncatingRemainder(dividingBy: step)
    if remainder < 0 { return remainder + step }
    if remainder == step { return 0 }
    return remainder
}

/// One dot cell. Rebuilt only when spacing or appearance changes, then painted with `ImagePaint`.
@MainActor
final class DotTileCache {
    private var step: CGFloat = .nan
    private var dark = false
    private var cached: Image?

    func image(step: CGFloat, scheme: ColorScheme) -> Image {
        let dark = scheme == .dark
        if let cached, self.step == step, self.dark == dark {
            return cached
        }
        let image = DotTileImage.make(step: step, dark: dark)
        self.step = step
        self.dark = dark
        cached = image
        return image
    }
}

private enum DotTileImage {
    static func make(step: CGFloat, dark: Bool) -> Image {
        let raster: CGFloat = 2
        let pixels = max(1, Int((step * raster).rounded()))
        let dotPixels = max(1, min(pixels, Int((2 * raster).rounded())))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: pixels * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let fallback = Image(systemName: "circle.fill")
        guard let context, let cgImage = paint(context, pixels: pixels, dotPixels: dotPixels, dark: dark) else {
            return fallback
        }
        let imageScale = CGFloat(pixels) / step
        return Image(decorative: cgImage, scale: imageScale)
    }

    private static func paint(
        _ context: CGContext,
        pixels: Int,
        dotPixels: Int,
        dark: Bool
    ) -> CGImage? {
        let alpha: CGFloat = dark ? 0.28 : 0.22
        let channel: CGFloat = dark ? 1 : 0
        context.setFillColor(red: channel, green: channel, blue: channel, alpha: alpha)
        let dot = CGFloat(dotPixels)
        let inset = (CGFloat(pixels) - dot) / 2
        context.fillEllipse(in: CGRect(x: inset, y: inset, width: dot, height: dot))
        return context.makeImage()
    }
}

/// Keeps the last layout so pan and zoom do not measure every node again.
@MainActor
final class LaidOutFrames {
    private var source: MindMapDocument?
    private var cached: [NodeFrame] = []

    func frames(for document: MindMapDocument) -> [NodeFrame] {
        if let source, source == document { return cached }
        cached = CanvasPlacement.nodes(in: document)
        source = document
        return cached
    }
}

/// Decoded thumbnails for nodes inside the viewport.
/// Scroll-out drops the `CGImage`. The disk LRU in `ThumbnailFileCache` stays.
@MainActor
@Observable
final class AttachmentThumbnailMemory {
    private(set) var images: [String: CGImage] = [:]
    private var bytes = ThumbnailMemory()
    private var visible: Set<String> = []
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    func image(for hash: String) -> CGImage? {
        images[hash]
    }

    func sync(
        visible: Set<String>,
        cache: ThumbnailFileCache?,
        archiveURL: URL?,
        spillDirectory: URL?,
        entries: [ZipStoredEntry]
    ) {
        self.visible = visible
        bytes.unload(keeping: visible)
        images = images.filter { visible.contains($0.key) }
        for hash in visible where images[hash] == nil && !inFlight.contains(hash) && !failed.contains(hash) {
            let plan = ImageDecodePlanKind.thumbnail(hash: hash)
            guard plan.storesInThumbnailCache else { continue }
            let entry = entries.first { $0.sha256 == hash }
            guard let entry,
                  let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension,
                  AttachmentKind.isImageExtension(ext) else { continue }
            guard cache != nil, archiveURL != nil, spillDirectory != nil else { continue }
            inFlight.insert(hash)
            let cache = cache
            let archiveURL = archiveURL
            let spillDirectory = spillDirectory
            let bridge = ThumbnailPublish(memory: self)
            ImageDecodeScheduler.submit(runner: ImageDecodeLane.detached) {
                let produced = AttachmentThumbnailMemory.produce(
                    entry: entry,
                    cache: cache,
                    archiveURL: archiveURL,
                    spillDirectory: spillDirectory
                )
                let image = produced.flatMap { ImageIOThumbnailDecoder.image(from: $0) }
                bridge.finish(hash: hash, box: DecodedThumb(data: produced, image: image))
            }
        }
    }

    /// Spill → ImageIO at the thumbnail edge → disk LRU. Runs off the main actor.
    nonisolated static func produce(
        entry: ZipStoredEntry,
        cache: ThumbnailFileCache?,
        archiveURL: URL?,
        spillDirectory: URL?
    ) -> Data? {
        if let cache, cache.contains(entry.sha256 ?? "") {
            let hash = entry.sha256 ?? ""
            try? cache.touch(hash)
            return try? Data(contentsOf: cache.fileURL(for: hash))
        }
        guard let cache, let archiveURL, let spillDirectory else { return nil }
        return try? ThumbnailPipeline.materialize(
            entry: entry,
            archiveURL: archiveURL,
            spillDirectory: spillDirectory,
            cache: cache,
            decoder: ImageIOThumbnailDecoder(),
            files: FoundationStreamingFiles()
        )
    }

    /// File-visible so `ThumbnailPublish` can hop the decoded image back onto this actor.
    fileprivate func finish(hash: String, box: DecodedThumb) {
        inFlight.remove(hash)
        guard let data = box.data, let image = box.image else {
            failed.insert(hash)
            return
        }
        bytes.remember(data, for: hash, visible: visible)
        if visible.contains(hash) {
            images[hash] = image
        }
    }
}

private struct DecodedThumb: @unchecked Sendable {
    var data: Data?
    var image: CGImage?
}

/// Hops a finished decode back to the main actor without decoding there.
private final class ThumbnailPublish: @unchecked Sendable {
    nonisolated(unsafe) private let memory: AttachmentThumbnailMemory

    init(memory: AttachmentThumbnailMemory) {
        self.memory = memory
    }

    func finish(hash: String, box: DecodedThumb) {
        let memory = memory
        Task { @MainActor in
            memory.finish(hash: hash, box: box)
        }
    }
}

enum ImagePlacement {
    static func rect(for image: CGImage, in node: CGRect) -> CGRect {
        let slot = ImageSlot.slot(nodeWidth: Double(node.width))
        let fitted = ImageAspectFit.fit(
            pixels: ImagePixelSize(width: image.width, height: image.height),
            in: slot
        )
        return CGRect(
            x: node.minX + CGFloat(fitted.x),
            y: node.minY + CGFloat(fitted.y),
            width: CGFloat(fitted.width),
            height: CGFloat(fitted.height)
        )
    }
}

/// Shared zoom state so the editor toolbar and the canvas stay on one camera.
@MainActor
@Observable
final class CanvasCamera {
    var viewport = CanvasViewport()
    var chrome = CanvasChrome.standard
    var viewSize: CGSize = .zero
    var contentBounds: CGRect?

    func stepZoom(_ direction: Int) {
        let anchor = center
        let next = ZoomStop.nearest(to: viewport.scale).stepped(direction)
        var updated = viewport
        updated.zoom(to: next.scale, around: anchor)
        viewport = updated
        chrome.syncZoomPercent(toScale: viewport.scale)
    }

    func resetZoom() {
        zoom(to: .oneHundred)
    }

    func zoom(to stop: ZoomStop) {
        var updated = viewport
        updated.zoom(to: stop.scale, around: center)
        viewport = updated
        chrome.syncZoomPercent(toScale: viewport.scale)
    }

    func fitToContent() {
        guard let contentBounds else { return }
        var updated = viewport
        updated.fit(content: contentBounds, in: viewSize)
        updated.snapToStop(around: center)
        viewport = updated
        chrome.syncZoomPercent(toScale: viewport.scale)
    }

    private var center: CGPoint {
        CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }
}

/// Hides the system focus ring without dropping keyboard focus.
struct CanvasFocusRingSuppressor: View {
    var body: some View {
        #if os(macOS)
        MacFocusRingSuppressor()
        #else
        Color.clear
        #endif
    }
}

#if os(macOS)
private struct MacFocusRingSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusRingFreeView {
        FocusRingFreeView()
    }

    func updateNSView(_ nsView: FocusRingFreeView, context: Context) {
        nsView.suppressFocusRing()
    }
}

private final class FocusRingFreeView: NSView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override func drawFocusRingMask() {}

    override var focusRingMaskBounds: NSRect { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        suppressFocusRing()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        suppressFocusRing()
    }

    override func layout() {
        super.layout()
        suppressFocusRing()
    }

    func suppressFocusRing() {
        guard let window else { return }
        var view: NSView? = self
        var steps = 0
        while let current = view, steps < 6, current !== window.contentView {
            current.focusRingType = .none
            view = current.superview
            steps += 1
        }
    }
}
#endif
