import FlorettaCore
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct InfiniteCanvas: View {
    @Binding var document: MindMapDocument

    @State private var drag: RootDrag?
    @State private var stickyDrag: StickyDrag?
    @State private var ignoreDrag = false
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
    var onPreviewFile: (UUID, FileBadge) -> Void = { _, _ in }
    var tagFilter: TopicTagFilter = TopicTagFilter()
    /// Markdown documents do not store free positions. Blank double-tap and root drag stay off.
    var persistsPlacement: Bool = true
    @State private var compositionWidth: CGFloat = 0
    @State private var fileIcons = FileIconCache()
    @State private var dotTiles = DotTileCache()
    @State private var laidOut = LaidOutFrames()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
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
            .overlay { stickyChrome }
            .overlay { stickyEditor }
            .overlay { relationshipEditor }
            .overlay { summaryEditor }
            .overlay { boundaryEditor }
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
                if let stickyHit = stickyHit(at: point) {
                    applyStickyTap(stickyHit)
                    return
                }
                if previewFile(at: point) { return }
                let hit = CanvasPlacement.nodeID(at: point, in: layoutSource())
                if hit == nil, let summaryID = summaryHit(at: point) {
                    applySummaryTap(summaryID)
                    return
                }
                if hit == nil, let relationshipID = relationshipHit(at: point) {
                    applyRelationshipTap(relationshipID)
                    return
                }
                if hit == nil, let boundaryID = boundaryHit(at: point) {
                    applyBoundaryTap(boundaryID)
                    return
                }
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
                if let id = stickyHit(at: point) {
                    beginStickyEdit(id)
                    return
                }
                if previewFile(at: point) { return }
                if let hit = CanvasPlacement.nodeID(at: point, in: layoutSource()) {
                    beginEditing(hit)
                    return
                }
                if let summaryID = summaryHit(at: point) {
                    if keyboard.mode == .edit, keyboard.selectedSummaryID != summaryID {
                        keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                    }
                    beginSummaryEdit(summaryID)
                    return
                }
                if let relationshipID = relationshipHit(at: point) {
                    if keyboard.mode == .edit, keyboard.selectedRelationshipID != relationshipID {
                        keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                    }
                    beginRelationshipEdit(relationshipID)
                    return
                }
                if let boundaryID = boundaryHit(at: point) {
                    if keyboard.mode == .edit, keyboard.selectedBoundaryID != boundaryID {
                        keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                    }
                    beginBoundaryEdit(boundaryID)
                    return
                }
                if onConsumeBlankDoubleTap() { return }
                if focusNodeID != nil { return }
                if keyboard.mode == .edit {
                    keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                }
                guard persistsPlacement else { return }
                let placed = MindMapPoint(x: Double(point.x), y: Double(point.y))
                if let id = keyboard.addFreeNode(at: placed, document: &document) {
                    keyboard.selectedNodeID = id
                    interaction.selectedNodeID = id
                }
            })
        }
        .focusEffectDisabled(true)
    }

    /// A tap on a file badge previews that file and does not open the text editor.
    private func previewFile(at point: CGPoint) -> Bool {
        guard let hit = CanvasPlacement.nodeID(at: point, in: layoutSource()),
              let frame = placedFrames().first(where: { $0.id == hit }),
              let badge = FileBadgeHit.badge(canvasX: Double(point.x), canvasY: Double(point.y), in: frame) else {
            return false
        }
        if keyboard.mode == .edit {
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
        }
        keyboard.selectedNodeID = hit
        interaction.selectedNodeID = hit
        onPreviewFile(hit, badge)
        return true
    }

    private func stickyHit(at point: CGPoint) -> UUID? {
        switch StickyGeometry.hit(x: Double(point.x), y: Double(point.y), in: document.stickies) {
        case .body(let id), .resize(let id):
            return id
        case nil:
            return nil
        }
    }

    private func applyStickyTap(_ id: UUID) {
        if keyboard.isComposing { return }
        if keyboard.mode == .edit {
            if keyboard.selectedStickyID == id { return }
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedStickyID = id
            interaction.selectedNodeID = nil
            return
        }
        if keyboard.selectedStickyID == id {
            beginStickyEdit(id)
            return
        }
        keyboard.selectedStickyID = id
        interaction.selectedNodeID = nil
    }

    private func applyRelationshipTap(_ id: UUID) {
        if keyboard.isComposing { return }
        if keyboard.mode == .edit {
            if keyboard.selectedRelationshipID == id { return }
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedRelationshipID = id
            interaction.selectedNodeID = nil
            canvasFocused = true
            return
        }
        if keyboard.selectedRelationshipID == id {
            beginRelationshipEdit(id)
            return
        }
        keyboard.selectedRelationshipID = id
        interaction.selectedNodeID = nil
    }

    private func applySummaryTap(_ id: UUID) {
        if keyboard.isComposing { return }
        if keyboard.mode == .edit {
            if keyboard.selectedSummaryID == id { return }
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedSummaryID = id
            interaction.selectedNodeID = nil
            return
        }
        if keyboard.selectedSummaryID == id {
            beginSummaryEdit(id)
            return
        }
        keyboard.selectedSummaryID = id
        interaction.selectedNodeID = nil
    }

    private func applyBoundaryTap(_ id: UUID) {
        if keyboard.isComposing { return }
        if keyboard.mode == .edit {
            if keyboard.selectedBoundaryID == id { return }
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedBoundaryID = id
            interaction.selectedNodeID = nil
            return
        }
        if keyboard.selectedBoundaryID == id {
            beginBoundaryEdit(id)
            return
        }
        keyboard.selectedBoundaryID = id
        interaction.selectedNodeID = nil
    }

    private func beginSummaryEdit(_ id: UUID) {
        keyboard.selectedSummaryID = id
        interaction.selectedNodeID = nil
        canvasFocused = false
        guard keyboard.mode != .edit else { return }
        keyboard.apply(.beginEdit, document: &document, frames: placedFrames())
    }

    private func beginBoundaryEdit(_ id: UUID) {
        keyboard.selectedBoundaryID = id
        interaction.selectedNodeID = nil
        canvasFocused = false
        guard keyboard.mode != .edit else { return }
        keyboard.apply(.beginEdit, document: &document, frames: placedFrames())
    }

    private func beginRelationshipEdit(_ id: UUID) {
        keyboard.selectedRelationshipID = id
        interaction.selectedNodeID = nil
        canvasFocused = false
        guard keyboard.mode != .edit else { return }
        keyboard.apply(.beginEdit, document: &document, frames: placedFrames())
    }

    private func beginStickyEdit(_ id: UUID) {
        keyboard.selectedStickyID = id
        interaction.selectedNodeID = nil
        canvasFocused = false
        guard keyboard.mode != .edit else { return }
        keyboard.apply(.beginEdit, document: &document, frames: placedFrames())
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
            if id == nil {
                keyboard.selectedRelationshipID = nil
                keyboard.selectedSummaryID = nil
                keyboard.selectedBoundaryID = nil
            }
            keyboard.selectedNodeID = id
            interaction.selectedNodeID = id
        case .beginEdit(let id):
            beginEditing(id)
        case .commitAndSelect(let id):
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            if id == nil {
                keyboard.selectedRelationshipID = nil
                keyboard.selectedSummaryID = nil
                keyboard.selectedBoundaryID = nil
            }
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
           !document.isInFreeNodeTree(id),
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

    @ViewBuilder
    private var stickyChrome: some View {
        if keyboard.mode == .command,
           let id = keyboard.selectedStickyID,
           let sticky = document.stickies.first(where: { $0.id == id }) {
            let rect = camera.viewport.viewRect(fromCanvas: CanvasPlacement.stickyCanvasRect(sticky))
            HStack(spacing: 6) {
                ForEach(StickyColor.palette, id: \.self) { color in
                    Button {
                        _ = keyboard.setStickyColor(color, id: id, document: &document)
                    } label: {
                        Circle()
                            .fill(stickyPaper(color))
                            .frame(width: 16, height: 16)
                            .overlay {
                                if sticky.color == color {
                                    Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(stickyColorName(color))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { Capsule().fill(.ultraThinMaterial) }
            .position(x: rect.midX, y: max(16, rect.minY - 18))
        }
    }

    @ViewBuilder
    private var stickyEditor: some View {
        if keyboard.mode == .edit,
           let id = keyboard.selectedStickyID,
           let sticky = document.stickies.first(where: { $0.id == id }) {
            let rect = camera.viewport.viewRect(fromCanvas: CanvasPlacement.stickyCanvasRect(sticky))
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(fontSize: 15, scale: camera.viewport.scale),
                onEvent: { handleKey($0) },
                returnInsertsLine: true,
                paper: stickyPaper(sticky.color),
                ink: stickyInk(sticky.color)
            )
            .frame(width: max(rect.width, 32), height: max(rect.height, 32))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private var relationshipEditor: some View {
        if keyboard.mode == .edit,
           keyboard.selectedRelationshipID != nil,
           let frame = relationshipEditFrame() {
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(
                    fontSize: RelationshipGeometry.labelFontSize,
                    scale: camera.viewport.scale
                ),
                onEvent: { handleKey($0) },
                paper: colorScheme == .dark ? Color(white: 0.16) : Color.white,
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private var summaryEditor: some View {
        if keyboard.mode == .edit,
           keyboard.editingSummaryID != nil,
           let frame = summaryEditFrame() {
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(
                    fontSize: SummaryGeometry.topicFontSize,
                    scale: camera.viewport.scale
                ),
                onEvent: { handleKey($0) },
                paper: colorScheme == .dark ? Color(white: 0.16) : Color.white,
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private var boundaryEditor: some View {
        if keyboard.mode == .edit,
           keyboard.editingBoundaryID != nil,
           let frame = boundaryEditFrame() {
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(
                    fontSize: SummaryGeometry.titleFontSize,
                    scale: camera.viewport.scale
                ),
                onEvent: { handleKey($0) },
                paper: colorScheme == .dark ? Color(white: 0.16) : Color.white,
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
            )
            .frame(width: max(frame.width, 72), height: max(frame.height, 22))
            .position(x: frame.midX, y: frame.midY)
        }
    }

    private func stickyChromeContains(_ viewPoint: CGPoint) -> Bool {
        guard keyboard.mode == .command,
              let id = keyboard.selectedStickyID,
              let sticky = document.stickies.first(where: { $0.id == id }) else { return false }
        let rect = camera.viewport.viewRect(fromCanvas: CanvasPlacement.stickyCanvasRect(sticky))
        let chrome = CGRect(x: rect.midX - 70, y: max(0, rect.minY - 34), width: 140, height: 32)
        return chrome.contains(viewPoint)
    }

    private func beginStickyDrag(at start: CGPoint) -> StickyDrag? {
        guard let hit = StickyGeometry.hit(x: Double(start.x), y: Double(start.y), in: document.stickies),
              let id = stickyID(hit),
              let sticky = document.stickies.first(where: { $0.id == id }) else { return nil }
        keyboard.beginStickyChange(document: document)
        keyboard.selectedStickyID = id
        interaction.selectedNodeID = nil
        return StickyDrag(
            id: id,
            resizing: isResize(hit),
            originX: sticky.origin.x,
            originY: sticky.origin.y,
            width: sticky.width,
            height: sticky.height,
            startX: Double(start.x),
            startY: Double(start.y)
        )
    }

    private func updateStickyDrag(_ drag: StickyDrag, to point: CGPoint) {
        let dx = Double(point.x) - drag.startX
        let dy = Double(point.y) - drag.startY
        if drag.resizing {
            _ = document.resizeSticky(drag.id, width: drag.width + dx, height: drag.height + dy)
        } else {
            _ = document.moveSticky(
                drag.id,
                to: MindMapPoint(x: drag.originX + dx, y: drag.originY + dy)
            )
        }
    }

    private func stickyID(_ hit: StickyHit) -> UUID? {
        switch hit {
        case .body(let id), .resize(let id):
            return id
        }
    }

    private func isResize(_ hit: StickyHit) -> Bool {
        if case .resize = hit { return true }
        return false
    }

    private func draw(_ sticky: StickyNote, in rect: CGRect, scale: CGFloat, context: GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: min(8, rect.height / 4))
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1))
        shadowed.fill(path, with: .color(stickyPaper(sticky.color)))
        let selected = keyboard.selectedStickyID == sticky.id
        context.stroke(
            path,
            with: .color(selected ? color(interaction.selectionBorder) : stickyInk(sticky.color).opacity(0.45)),
            lineWidth: selected ? 2 : 1
        )
        let editing = keyboard.mode == .edit && selected
        let textRect = rect.insetBy(dx: 10 * max(scale, 0.5), dy: 8 * max(scale, 0.5))
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: 15, scale: scale)
        if !editing, CanvasTextLOD.level(onScreenPointSize: pointSize).drawsTitle,
           textRect.width > 1, textRect.height > 1, !sticky.text.isEmpty {
            var layer = context
            layer.clip(to: Path(textRect))
            layer.draw(
                Text(sticky.text)
                    .font(.system(size: pointSize))
                    .foregroundStyle(stickyInk(sticky.color)),
                in: textRect
            )
        }
        if selected, keyboard.mode == .command {
            let handle = CGRect(x: rect.maxX - 10, y: rect.maxY - 10, width: 7, height: 7)
            context.fill(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(stickyInk(sticky.color)))
        }
    }

    private func stickyPaper(_ color: StickyColor) -> Color {
        Color(red: color.fill.red, green: color.fill.green, blue: color.fill.blue)
    }

    private func stickyInk(_ color: StickyColor) -> Color {
        Color(red: color.ink.red, green: color.ink.green, blue: color.ink.blue)
    }

    private func stickyColorName(_ color: StickyColor) -> String {
        let key: String
        switch color {
        case .yellow: key = "黄色"
        case .pink: key = "粉色"
        case .green: key = "绿色"
        case .blue: key = "蓝色"
        case .orange: key = "橙色"
        }
        return FlorettaL10n.string(key, locale: locale)
    }

    /// View rect of the system text field, including the extra width used while
    /// marked text is wider than the topic.
    private func editFieldFrame() -> CGRect? {
        if keyboard.mode == .edit, keyboard.selectedRelationshipID != nil, let frame = relationshipEditFrame() {
            return frame
        }
        if keyboard.mode == .edit, keyboard.selectedSummaryID != nil, let frame = summaryEditFrame() {
            return frame
        }
        if keyboard.mode == .edit, keyboard.selectedBoundaryID != nil, let frame = boundaryEditFrame() {
            return frame
        }
        guard keyboard.mode == .edit,
              let id = keyboard.selectedNodeID,
              let frame = placedFrames().first(where: { $0.id == id }) else { return nil }
        let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
        let width = max(rect.width, compositionWidth, 88)
        let height = max(rect.height, 36)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private func summaryEditFrame() -> CGRect? {
        guard let id = keyboard.selectedSummaryID else { return nil }
        let frames = placedFrames()
        guard let mark = SummaryGeometry.summaries(in: document, frames: frames).first(where: { $0.id == id }) else {
            return nil
        }
        return camera.viewport.viewRect(fromCanvas: mark.topicRect)
    }

    private func boundaryEditFrame() -> CGRect? {
        guard let id = keyboard.selectedBoundaryID else { return nil }
        let frames = placedFrames()
        guard let mark = SummaryGeometry.boundaries(in: document, frames: frames).first(where: { $0.id == id }) else {
            return nil
        }
        let rect = mark.titleRect.width > 1 ? mark.titleRect : CGRect(
            x: mark.rect.midX - 48,
            y: mark.rect.minY - 12,
            width: 96,
            height: 22
        )
        return camera.viewport.viewRect(fromCanvas: rect)
    }

    private func relationshipEditFrame() -> CGRect? {
        guard let id = keyboard.selectedRelationshipID else { return nil }
        let frames = placedFrames()
        guard let line = relationshipLines(in: frames).first(where: { $0.id == id }) else { return nil }
        let straight = CanvasDrawPolicy.useStraightLink(nodeCount: frames.count, link: line.curve)
        let center = camera.viewport.viewPoint(fromCanvas: line.labelCenter(straight: straight))
        let canvasRect = RelationshipLine.labelRect(center: line.labelCenter(straight: straight), size: line.labelSize)
        let mapped = camera.viewport.viewRect(fromCanvas: canvasRect)
        let width = max(mapped.width, compositionWidth, 88)
        let height = max(mapped.height, 28)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    private func placedFrames() -> [NodeFrame] {
        laidOut.frames(for: layoutSource(), scheme: branchScheme)
    }

    private var branchScheme: MapColorScheme {
        colorScheme == .dark ? .dark : .light
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
                if drag == nil && panAnchor == nil && stickyDrag == nil && !ignoreDrag {
                    let start = camera.viewport.canvasPoint(fromView: value.startLocation)
                    if keyboard.mode == .edit, let frame = editFieldFrame(), frame.contains(value.startLocation) {
                        ignoreDrag = true
                        return
                    }
                    let onEditedSticky = keyboard.mode == .edit
                        && stickyHit(at: start) != nil
                        && stickyHit(at: start) == keyboard.selectedStickyID
                    if stickyChromeContains(value.startLocation) || onEditedSticky {
                        ignoreDrag = true
                    } else if persistsPlacement, keyboard.mode != .edit, let claim = beginStickyDrag(at: start) {
                        stickyDrag = claim
                    } else if persistsPlacement,
                              let id = CanvasPlacement.draggableID(at: start, in: layoutSource()),
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
                if let stickyDrag {
                    let point = camera.viewport.canvasPoint(fromView: value.location)
                    updateStickyDrag(stickyDrag, to: point)
                } else if let drag {
                    let point = camera.viewport.canvasPoint(fromView: value.location)
                    let origin = CGPoint(x: point.x - drag.grabX, y: point.y - drag.grabY)
                    document = CanvasPlacement.movingNode(drag.id, to: origin, in: document)
                } else if let panAnchor {
                    camera.viewport.offset = CGPoint(
                        x: panAnchor.x + value.translation.width,
                        y: panAnchor.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if stickyDrag != nil {
                    keyboard.commitStickyChange(document: document)
                }
                drag = nil
                stickyDrag = nil
                panAnchor = nil
                ignoreDrag = false
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
        let boundaryMarks = document.hasBoundaries
            ? SummaryGeometry.boundaries(in: document, frames: placed)
            : []
        let summaryMarks = document.hasSummaries
            ? SummaryGeometry.summaries(in: document, frames: placed)
            : []
        let scale = camera.viewport.scale
        if !boundaryMarks.isEmpty {
            let viewBounds = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for mark in boundaryMarks {
                let box = camera.viewport.viewRect(fromCanvas: mark.bounds)
                guard box.intersects(viewBounds) else { continue }
                drawBoundary(mark, scale: scale, in: context)
            }
        }
        let viewport = camera.viewport.canvasRect(in: size).insetBy(dx: -48, dy: -48)
        let visible = CanvasPlacement.frames(placed, intersectingCanvas: viewport)
        let linkIDs = CanvasPlacement.nodeIDsWithVisibleLinks(placed, viewport: viewport)
        for node in placed where linkIDs.contains(node.id) {
            guard let link = node.link else { continue }
            stroke(
                link,
                straight: CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                in: context
            )
        }
        let relationships = relationshipLines(in: placed)
        let straightRelationship: (RelationshipLine) -> Bool = { line in
            CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: line.curve)
        }
        if !relationships.isEmpty {
            let viewBounds = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for line in relationships {
                let box = camera.viewport.viewRect(fromCanvas: line.bounds)
                guard box.intersects(viewBounds) else { continue }
                stroke(
                    line,
                    straight: straightRelationship(line),
                    selected: keyboard.selectedRelationshipID == line.id,
                    in: context
                )
            }
        }
        let highlightedIDs = tagFilter.isActive ? tagFilter.highlightedIDs(in: document) : []
        for node in visible {
            let onScreen = min(node.size.width, node.size.height) * scale
            let highlighted = tagFilter.isActive && highlightedIDs.contains(node.id)
            let dimmed = tagFilter.isActive && !highlighted && interaction.selectedNodeID != node.id
            draw(
                node,
                detail: CanvasDetail.level(scale: scale, onScreenHeight: onScreen),
                scale: scale,
                highlighted: highlighted,
                dimmed: dimmed,
                in: context
            )
        }
        if !relationships.isEmpty, RelationshipGeometry.labelFontSize * scale >= 9 {
            let labelViewport = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for line in relationships where !line.title.isEmpty {
                let straight = straightRelationship(line)
                if keyboard.mode == .edit, keyboard.selectedRelationshipID == line.id { continue }
                let canvasRect = RelationshipLine.labelRect(
                    center: line.labelCenter(straight: straight),
                    size: line.labelSize
                )
                guard camera.viewport.viewRect(fromCanvas: canvasRect).intersects(labelViewport) else { continue }
                drawLabel(line, straight: straight, scale: scale, in: context)
            }
        }
        if !summaryMarks.isEmpty {
            let summaryViewport = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for mark in summaryMarks {
                guard camera.viewport.viewRect(fromCanvas: mark.bounds).intersects(summaryViewport) else { continue }
                drawSummary(mark, scale: scale, in: context)
            }
        }
        let viewBounds = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
        for sticky in document.stickies {
            let rect = camera.viewport.viewRect(fromCanvas: CanvasPlacement.stickyCanvasRect(sticky))
            guard rect.intersects(viewBounds) else { continue }
            draw(sticky, in: rect, scale: scale, context: context)
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

    private func stroke(_ line: RelationshipLine, straight: Bool, selected: Bool, in context: GraphicsContext) {
        var path = Path()
        let start = camera.viewport.viewPoint(fromCanvas: line.curve.start)
        let end = camera.viewport.viewPoint(fromCanvas: line.curve.end)
        path.move(to: start)
        if straight {
            path.addLine(to: end)
        } else {
            path.addCurve(
                to: end,
                control1: camera.viewport.viewPoint(fromCanvas: line.curve.control1),
                control2: camera.viewport.viewPoint(fromCanvas: line.curve.control2)
            )
        }
        let ink = selected ? color(interaction.selectionBorder) : color(line.curve.color)
        let width = selected ? line.curve.lineWidth + 0.75 : line.curve.lineWidth
        let style = StrokeStyle(lineWidth: width, lineCap: .round, dash: selected ? [] : [7, 5])
        context.stroke(path, with: .color(ink), style: style)
        let from = straight ? line.curve.start : line.curve.control2
        let head = RelationshipGeometry.arrow(tip: line.curve.end, from: from)
        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: camera.viewport.viewPoint(fromCanvas: head.left))
        arrow.addLine(to: camera.viewport.viewPoint(fromCanvas: head.right))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(ink))
    }

    private func drawLabel(_ line: RelationshipLine, straight: Bool, scale: CGFloat, in context: GraphicsContext) {
        let canvasRect = RelationshipLine.labelRect(center: line.labelCenter(straight: straight), size: line.labelSize)
        let rect = camera.viewport.viewRect(fromCanvas: canvasRect)
        guard rect.width > 1, rect.height > 1 else { return }
        let paper = colorScheme == .dark ? Color(white: 0.16) : Color.white
        let ink = colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
        let path = Path(roundedRect: rect, cornerRadius: min(6, rect.height / 2))
        context.fill(path, with: .color(paper))
        let selected = keyboard.selectedRelationshipID == line.id
        let border = selected ? color(interaction.selectionBorder) : color(RelationshipGeometry.ink).opacity(0.45)
        context.stroke(path, with: .color(border), lineWidth: selected ? 1.5 : 1)
        let textRect = rect.insetBy(dx: 4, dy: 2)
        guard textRect.width > 1, textRect.height > 1 else { return }
        context.draw(
            Text(line.title)
                .font(.system(size: CanvasTextScale.onScreenPointSize(
                    fontSize: RelationshipGeometry.labelFontSize,
                    scale: scale
                )))
                .foregroundStyle(ink),
            in: textRect
        )
    }

    private func drawBoundary(_ mark: BoundaryMark, scale: CGFloat, in context: GraphicsContext) {
        let rect = camera.viewport.viewRect(fromCanvas: mark.rect)
        guard rect.width > 1, rect.height > 1 else { return }
        let path = Path(roundedRect: rect, cornerRadius: SummaryGeometry.cornerRadius)
        let selected = keyboard.selectedBoundaryID == mark.id
        let ink = selected ? color(interaction.selectionBorder) : color(SummaryGeometry.boundaryInk)
        context.fill(path, with: .color(ink.opacity(colorScheme == .dark ? 0.16 : 0.08)))
        context.stroke(path, with: .color(ink), lineWidth: selected ? 2.25 : SummaryGeometry.lineWidth)
        let titleSize = CanvasTextScale.onScreenPointSize(fontSize: SummaryGeometry.titleFontSize, scale: scale)
        guard titleSize >= 9, !mark.title.isEmpty, keyboard.editingBoundaryID != mark.id else { return }
        let title = camera.viewport.viewRect(fromCanvas: mark.titleRect)
        guard title.width > 1, title.height > 1 else { return }
        let paper = colorScheme == .dark ? Color(white: 0.16) : Color.white
        let textInk = colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
        context.fill(Path(roundedRect: title, cornerRadius: 4), with: .color(paper))
        context.draw(
            Text(mark.title).font(.system(size: titleSize)).foregroundStyle(textInk),
            in: title.insetBy(dx: 4, dy: 1)
        )
    }

    private func drawSummary(_ mark: SummaryMark, scale: CGFloat, in context: GraphicsContext) {
        var brace = Path()
        brace.move(to: camera.viewport.viewPoint(fromCanvas: mark.braceTop))
        brace.addLine(to: camera.viewport.viewPoint(fromCanvas: mark.braceMid))
        brace.addLine(to: camera.viewport.viewPoint(fromCanvas: mark.braceBottom))
        let selected = keyboard.selectedSummaryID == mark.id
        let ink = selected ? color(interaction.selectionBorder) : color(SummaryGeometry.summaryInk)
        context.stroke(
            brace,
            with: .color(ink),
            style: StrokeStyle(lineWidth: selected ? 2.25 : SummaryGeometry.lineWidth, lineCap: .round, lineJoin: .round)
        )
        let rect = camera.viewport.viewRect(fromCanvas: mark.topicRect)
        guard rect.width > 1, rect.height > 1 else { return }
        let card = Path(roundedRect: rect, cornerRadius: 8)
        let paper = colorScheme == .dark ? Color(white: 0.16) : Color.white
        let textInk = colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
        context.fill(card, with: .color(paper))
        context.stroke(card, with: .color(ink), lineWidth: selected ? 2.25 : SummaryGeometry.lineWidth)
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: SummaryGeometry.topicFontSize, scale: scale)
        guard pointSize >= 9, !mark.text.isEmpty, keyboard.editingSummaryID != mark.id else { return }
        let textRect = rect.insetBy(dx: 6, dy: 3)
        guard textRect.width > 1, textRect.height > 1 else { return }
        context.draw(
            Text(mark.text)
                .font(.system(size: pointSize))
                .foregroundStyle(textInk),
            in: textRect
        )
    }

    private func summaryHit(at point: CGPoint) -> UUID? {
        guard document.hasSummaries else { return nil }
        return SummaryGeometry.summaryHit(
            at: point,
            in: SummaryGeometry.summaries(in: document, frames: placedFrames())
        )
    }

    private func boundaryHit(at point: CGPoint) -> UUID? {
        guard document.hasBoundaries else { return nil }
        return SummaryGeometry.boundaryHit(
            at: point,
            in: SummaryGeometry.boundaries(in: document, frames: placedFrames())
        )
    }

    private func relationshipLines(in frames: [NodeFrame]) -> [RelationshipLine] {
        guard !document.relationships.isEmpty else { return [] }
        return RelationshipGeometry.lines(for: document.relationships, frames: frames)
    }

    private func relationshipHit(at point: CGPoint) -> UUID? {
        let frames = placedFrames()
        let lines = relationshipLines(in: frames)
        guard !lines.isEmpty else { return nil }
        let slop = max(RelationshipGeometry.hitSlop, 12 / max(camera.viewport.scale, 0.25))
        return RelationshipGeometry.hit(at: point, in: lines, straight: { line in
            CanvasDrawPolicy.useStraightLink(nodeCount: frames.count, link: line.curve)
        }, slop: slop)
    }

    private func draw(
        _ node: NodeFrame,
        detail: CanvasDetail,
        scale: CGFloat,
        highlighted: Bool,
        dimmed: Bool,
        in context: GraphicsContext
    ) {
        let rect = camera.viewport.viewRect(fromCanvas: node.frame)
        let path = Path(roundedRect: rect, cornerRadius: detail == .far ? min(node.cornerRadius, 4) : node.cornerRadius)
        let selected = interaction.selectedNodeID == node.id
        var layer = context
        if dimmed { layer.opacity = TopicTagCanvas.dimOpacity }
        if !node.hidesFill {
            if detail.drawsShadow {
                var shadowed = layer
                shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5))
                shadowed.fill(path, with: .color(color(node.fill)))
            } else {
                layer.fill(path, with: .color(color(node.fill)))
            }
        }
        if detail != .far, selected {
            layer.stroke(
                path,
                with: .color(color(interaction.selectionBorder)),
                lineWidth: interaction.selectionBorderWidth
            )
        } else if detail.drawsFineBorder || (detail == .mid && node.borderWidth >= 2.5) {
            if node.borderWidth > 0 {
                layer.stroke(path, with: .color(color(node.border)), lineWidth: node.borderWidth)
            }
        }
        if highlighted, detail != .far {
            context.stroke(path, with: .color(color(TopicTagCanvas.highlight)), lineWidth: 2.5)
        }
        if selected, detail.drawsSelectionHandles {
            drawHandles(around: rect, in: context)
        }
        var textRect = rect.insetBy(dx: 6, dy: 4)
        if detail != .far,
           let hash = node.thumbnailHashes.first,
           let image = thumbnails?.image(for: hash) {
            let imageRect = ImagePlacement.rect(for: image, in: rect)
            layer.draw(Image(decorative: image, scale: 1), in: imageRect)
            textRect = CGRect(
                x: rect.minX + 6,
                y: imageRect.maxY + 2,
                width: max(0, rect.width - 12),
                height: max(0, rect.maxY - imageRect.maxY - 6)
            )
        }
        if detail.drawsText, let first = node.fileBadges.first {
            let badgeTop = camera.viewport.viewPoint(fromCanvas: CGPoint(
                x: node.origin.x,
                y: node.origin.y + CGFloat(first.row.y)
            )).y
            textRect.size.height = max(0, min(textRect.maxY, badgeTop - 2) - textRect.minY)
        }
        if detail.drawsText, node.tagBandHeight > 0 {
            let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: node.fileBadges.count))
            let tagTop = node.origin.y + node.size.height - fileBand - node.tagBandHeight
            let tagY = camera.viewport.viewPoint(fromCanvas: CGPoint(x: node.origin.x, y: tagTop)).y
            textRect.size.height = max(0, min(textRect.maxY, tagY - 2) - textRect.minY)
        }
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: node.fontSize, scale: scale)
        if CanvasTextLOD.level(onScreenPointSize: pointSize).drawsTitle, textRect.height > 1, textRect.width > 1 {
            let text = styledText(node, pointSize: pointSize)
            var textLayer = layer
            textLayer.clip(to: Path(textRect))
            textLayer.draw(text, at: CGPoint(x: textRect.midX, y: textRect.midY), anchor: .center)
        }
        if detail.drawsText {
            drawFileBadges(node, scale: scale, pointSize: pointSize, in: layer)
            TopicTagCanvas.draw(node: node, in: rect, context: layer, color: color, ink: color(node.textColor))
        }
    }

    private func drawFileBadges(_ node: NodeFrame, scale: CGFloat, pointSize: CGFloat, in context: GraphicsContext) {
        guard !node.fileBadges.isEmpty else { return }
        let badgePoint = max(9, min(13, pointSize * 0.72))
        for badge in node.fileBadges {
            let row = viewLocal(badge.row, node: node)
            let icon = viewLocal(badge.icon, node: node)
            context.draw(fileIcons.image(for: badge), in: icon)
            let sizeWidth = min(row.width * 0.46, max(28, CGFloat(badge.sizeLabel.count) * badgePoint * 0.62))
            let sizeRect = CGRect(x: row.maxX - sizeWidth, y: row.minY, width: sizeWidth, height: row.height)
            let nameX = icon.maxX + 4 * max(scale, 0.5)
            let nameRect = CGRect(x: nameX, y: row.minY, width: max(0, sizeRect.minX - nameX - 4), height: row.height)
            let name = Text(badge.filename)
                .font(.system(size: badgePoint))
                .foregroundStyle(color(node.textColor))
            let size = Text(badge.sizeLabel)
                .font(.system(size: badgePoint))
                .foregroundStyle(color(node.textColor).opacity(0.72))
            var nameLayer = context
            nameLayer.clip(to: Path(nameRect))
            nameLayer.draw(name, at: CGPoint(x: nameRect.minX, y: nameRect.midY), anchor: .leading)
            var sizeLayer = context
            sizeLayer.clip(to: Path(sizeRect))
            sizeLayer.draw(size, at: CGPoint(x: sizeRect.maxX, y: sizeRect.midY), anchor: .trailing)
        }
    }

    private func viewLocal(_ local: ImageSlotRect, node: NodeFrame) -> CGRect {
        let origin = camera.viewport.viewPoint(fromCanvas: CGPoint(
            x: node.origin.x + CGFloat(local.x),
            y: node.origin.y + CGFloat(local.y)
        ))
        let far = camera.viewport.viewPoint(fromCanvas: CGPoint(
            x: node.origin.x + CGFloat(local.x + local.width),
            y: node.origin.y + CGFloat(local.y + local.height)
        ))
        return CGRect(x: origin.x, y: origin.y, width: max(0, far.x - origin.x), height: max(0, far.y - origin.y))
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
        let nodes = laidOut.frames(for: document, scheme: branchScheme).map { frame in
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
        let shown = NodeAttachmentDrawing.canvasText(
            title: node.text,
            caption: node.caption,
            fileBadges: node.fileBadges
        )
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

private struct StickyDrag {
    var id: UUID
    var resizing: Bool
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double
    var startX: Double
    var startY: Double
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

enum TopicTagCanvas {
    static let highlight = BranchColor(red: 196.0 / 255, green: 92.0 / 255, blue: 38.0 / 255)
    static let dimOpacity = 0.28

    static func draw(
        node: NodeFrame,
        in rect: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color,
        ink: Color
    ) {
        guard node.tagBandHeight > 0, node.size.height > 1, rect.width > 8, rect.height > 8 else { return }
        let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: node.fileBadges.count))
        let scaleY = rect.height / node.size.height
        let scaleX = rect.width / max(node.size.width, 1)
        let tagHeight = node.tagBandHeight * scaleY
        let fileHeight = fileBand * scaleY
        let inset = 6 * min(scaleX, 1.4)
        var cursor = CGRect(
            x: rect.minX + inset,
            y: rect.maxY - fileHeight - tagHeight,
            width: max(0, rect.width - inset * 2),
            height: tagHeight
        )
        let gap = CGFloat(TopicTagLayout.gap) * scaleY
        cursor.origin.y += gap
        cursor.size.height = max(0, cursor.height - gap)
        let row = CGFloat(TopicTagLayout.rowHeight) * scaleY
        guard cursor.width > 1, row > 1 else { return }
        if !node.markerIDs.isEmpty {
            drawMarkers(
                node.markerIDs,
                in: CGRect(x: cursor.minX, y: cursor.minY, width: cursor.width, height: row),
                context: context,
                color: color
            )
            cursor.origin.y += row
            cursor.size.height = max(0, cursor.height - row)
        }
        guard !node.labels.isEmpty, cursor.height > 1 else { return }
        let box = CGRect(x: cursor.minX, y: cursor.minY, width: cursor.width, height: min(row, cursor.height))
        var layer = context
        layer.clip(to: Path(box))
        let point = max(8, min(13, box.height * 0.8))
        layer.draw(
            Text(node.labels.joined(separator: "  "))
                .font(.system(size: point))
                .foregroundStyle(ink),
            at: CGPoint(x: box.minX, y: box.midY),
            anchor: .leading
        )
    }

    private static func drawMarkers(
        _ markerIDs: [String],
        in row: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color
    ) {
        let side = min(row.height - 1, 14)
        guard side > 3 else { return }
        var x = row.minX
        for markerId in markerIDs {
            if x + side > row.maxX { break }
            let mark = CGRect(x: x, y: row.midY - side / 2, width: side, height: side)
            drawMarker(markerId, in: mark, context: context, color: color)
            x += side + 3
        }
    }

    private static func drawMarker(
        _ markerId: String,
        in mark: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color
    ) {
        if let fraction = TopicMarkerCatalog.progressFraction(markerId) {
            let track = BranchColor(red: 0.62, green: 0.64, blue: 0.66)
            let fill = BranchColor(red: 0.18, green: 0.62, blue: 0.32)
            context.stroke(Path(ellipseIn: mark), with: .color(color(track)), lineWidth: 1)
            if fraction >= 1 {
                context.fill(Path(ellipseIn: mark.insetBy(dx: 1, dy: 1)), with: .color(color(fill)))
            } else if fraction > 0 {
                context.fill(pie(in: mark.insetBy(dx: 1, dy: 1), fraction: fraction), with: .color(color(fill)))
            }
            return
        }
        if TopicMarkerCatalog.group(of: markerId) == .flag, let flag = TopicMarkerCatalog.color(for: markerId) {
            var cloth = Path()
            cloth.move(to: CGPoint(x: mark.minX + 1, y: mark.minY))
            cloth.addLine(to: CGPoint(x: mark.maxX, y: mark.midY))
            cloth.addLine(to: CGPoint(x: mark.minX + 1, y: mark.maxY))
            cloth.closeSubpath()
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: mark.minX + 1, y: mark.minY))
                    path.addLine(to: CGPoint(x: mark.minX + 1, y: mark.maxY))
                },
                with: .color(color(flag)),
                lineWidth: 1.25
            )
            context.fill(cloth, with: .color(color(flag)))
            return
        }
        let ink = TopicMarkerCatalog.color(for: markerId) ?? BranchColor(red: 0.45, green: 0.47, blue: 0.50)
        context.fill(Path(ellipseIn: mark), with: .color(color(ink)))
        if let number = TopicMarkerCatalog.priorityNumber(markerId), mark.height >= 8 {
            context.draw(
                Text("\(number)")
                    .font(.system(size: max(7, mark.height * 0.62)))
                    .foregroundStyle(Color.white),
                at: CGPoint(x: mark.midX, y: mark.midY),
                anchor: .center
            )
        }
    }

    private static func pie(in rect: CGRect, fraction: Double) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
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

    private var cachedScheme: MapColorScheme?

    func frames(for document: MindMapDocument, scheme: MapColorScheme) -> [NodeFrame] {
        if let source, source == document, cachedScheme == scheme { return cached }
        cached = CanvasPlacement.nodes(in: document, scheme: scheme)
        source = document
        cachedScheme = scheme
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
