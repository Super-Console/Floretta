import FlorettaCore
import Observation
import SwiftUI
import AVKit
import AVFoundation
import ImageIO
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct InfiniteCanvas: View {
    @Binding var document: MindMapDocument

    @State private var drag: RootDrag?
    @State private var stickyDrag: StickyDrag?
    @State private var regionDrag: RegionDrag?
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
    var audioPlayer: AVPlayer? = nil
    var audioNodeID: UUID? = nil
    var onDismissAudio: () -> Void = {}
    var tagFilter: TopicTagFilter = TopicTagFilter()
    /// Markdown documents do not store free positions. Blank double-tap and root drag stay off.
    var persistsPlacement: Bool = true
    var dictationToken: Int = 0
    var dictationReplacesPlaceholder: Bool = false
    @State private var compositionWidth: CGFloat = 0
    @State private var fileIcons = FileIconCache()
    @State private var dotTiles = DotTileCache()
    @State private var laidOut = LaidOutFrames()
    /// One petal plan for map open and branch expand/collapse. Pan, zoom, and typing do not start it.
    @State private var petal = PetalExpandDirector(reduceMotion: false)
    @State private var petalFrames: [NodeFrame] = []
    @State private var petalPrint = CollapseFingerprint.empty
    /// False until the open transition is armed, so the first frame is not a fully drawn map that then snaps into a bud.
    @State private var petalMapOpened = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @FocusState private var canvasFocused: Bool

    var body: some View {
        GeometryReader { geo in
            observeCanvas(canvasSurface(size: geo.size), size: geo.size)
        }
        .focusEffectDisabled(true)
    }

    private func canvasSurface(size: CGSize) -> some View {
        canvasVisuals
        .gesture(dragGesture)
        .simultaneousGesture(pinchGesture(in: size))
        .overlay {
            CanvasScrollCatcher { delta, location, command in
                camera.viewport.applyScroll(delta: delta, around: location, command: command)
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            }
        }
        .overlay { if !zenActive { hoverAddButtons } }
        .overlay { editField }
        .overlay { nodeChromeProbe }
        .overlay { stickyChrome }
        .overlay { stickyEditor }
        .overlay { regionToolbar }
        .overlay { regionEditor }
        .overlay { relationshipEditor }
        .overlay { summaryEditor }
        .overlay { boundaryEditor }
        .overlay { audioPlaybackOverlay }
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
    }

    private var canvasVisuals: some View {
        canvasPaper.overlay { canvasTimeline }
    }

    private var canvasPaper: some View {
        paperLayer
            .contentShape(Rectangle())
            .accessibilityIdentifier("editor.canvas")
    }

    private var canvasTimeline: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !petal.isPlaying)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
            .onChange(of: timeline.date) { _, date in
                let time = date.timeIntervalSinceReferenceDate
                let extra = petal.layoutExtra(comparedTo: laidOut.layoutPassCount)
                if extra != petal.layoutPassesDuringPlayback {
                    petal.noteLayoutExtra(extra)
                }
                if petal.playbackDidFinish(at: time) {
                    petal.settle()
                }
            }
        }
    }

    private func observeCanvas<V: View>(_ view: V, size: CGSize) -> some View {
        view
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
                camera.viewSize = size
                publishBounds()
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
                refreshThumbnails()
                openPetalMap()
                canvasFocused = true
            }
            .onChange(of: size) { _, newSize in
                camera.viewSize = newSize
                refreshThumbnails()
            }
            .onChange(of: document) { _, newDocument in
                let nextPrint = CollapseFingerprint.capture(newDocument)
                let frames = placedFrames()
                petal.noteDocumentChange(
                    from: petalPrint,
                    to: nextPrint,
                    previousFrames: petalFrames,
                    finalFrames: frames,
                    now: Date().timeIntervalSinceReferenceDate,
                    layoutPassCount: laidOut.layoutPassCount
                )
                petalPrint = nextPrint
                petalFrames = frames
                publishBounds()
                refreshThumbnails()
            }
            .onChange(of: focusNodeID) { _, _ in
                petal.settle()
                petalFrames = placedFrames()
                publishBounds()
            }
            .onChange(of: reduceMotion) { _, enabled in
                petal.setReduceMotion(enabled)
                if enabled { petalMapOpened = true }
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
            .simultaneousGesture(canvasTapGesture)
            .simultaneousGesture(canvasDoubleTapGesture)
    }

    private var canvasTapGesture: some Gesture {
        SpatialTapGesture().onEnded { value in
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
            if hit == nil, let regionID = regionHit(at: point) {
                applyRegionTap(regionID)
                return
            }
            if zenActive, hit == nil { return }
            applyNodeTap(hit)
        }
    }

    private var canvasDoubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
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
            if let regionID = regionHit(at: point),
               CanvasPlacement.nodeID(at: point, in: layoutSource()) == nil {
                if keyboard.mode == .edit, keyboard.selectedRegionID != regionID {
                    keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
                }
                beginRegionEdit(regionID)
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
        }
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

    private func applyRegionTap(_ id: UUID) {
        if keyboard.isComposing { return }
        if keyboard.mode == .edit {
            if keyboard.selectedRegionID == id { return }
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            keyboard.selectedRegionID = id
            interaction.selectedNodeID = nil
            return
        }
        if keyboard.selectedRegionID == id {
            beginRegionEdit(id)
            return
        }
        keyboard.selectedRegionID = id
        interaction.selectedNodeID = nil
    }

    private func beginRegionEdit(_ id: UUID) {
        keyboard.selectedRegionID = id
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

    /// Map open. A later collapse toggle goes through `noteDocumentChange`.
    /// Reduce Motion settles on the layout with no clock.
    private func openPetalMap() {
        let frames = placedFrames()
        petalFrames = frames
        petalPrint = CollapseFingerprint.capture(document)
        guard !petalMapOpened else { return }
        petal.setReduceMotion(reduceMotion)
        petal.openMap(
            frames: frames,
            now: Date().timeIntervalSinceReferenceDate,
            layoutPassCount: laidOut.layoutPassCount
        )
        petalMapOpened = true
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
            let editor = NodeEditChrome.editorFrame(node: rect, compositionWidth: compositionWidth)
            let pointSize = CanvasTextScale.onScreenPointSize(
                fontSize: frame.fontSize,
                scale: camera.viewport.scale
            )
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: pointSize,
                onEvent: { handleKey($0) },
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder,
                nodeChrome: NodeEditSurface(
                    fill: frame.fill,
                    textColor: frame.textColor,
                    hidesFill: frame.hidesFill,
                    cornerRadius: frame.cornerRadius,
                    fontSize: pointSize,
                    fontDesign: frame.fontDesign,
                    bold: frame.bold,
                    italic: frame.italic,
                    strikethrough: frame.strikethrough,
                    underline: frame.underline
                )
            )
            .frame(width: editor.width, height: editor.height)
            .clipShape(RoundedRectangle(cornerRadius: frame.cornerRadius, style: .circular))
            .overlay {
                if frame.borderWidth > 0 {
                    RoundedRectangle(cornerRadius: frame.cornerRadius, style: .circular)
                        .strokeBorder(color(frame.border), lineWidth: frame.borderWidth)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: frame.cornerRadius, style: .circular)
                    .stroke(Color.accentColor, lineWidth: NodeEditChrome.selectionStrokeWidth)
            }
            .position(x: editor.midX, y: editor.midY)
        }
    }

    /// Idle read-out of the selected node's painted frame and fill.
    /// Editing publishes the same identifier from the text view's real background.
    @ViewBuilder
    private var nodeChromeProbe: some View {
        if keyboard.mode != .edit,
           let id = keyboard.selectedNodeID,
           let frame = placedFrames().first(where: { $0.id == id }) {
            let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
            NodeChromeProbeBox(
                value: NodeEditChrome.accessibilityValue(editing: false, fill: frame.fill, size: rect.size)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
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
            .appleGlassChrome(.bottomBarCapsule)
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
                ink: stickyInk(sticky.color),
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder
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
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16),
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder
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
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16),
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder
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
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16),
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder
            )
            .frame(width: max(frame.width, 72), height: max(frame.height, 22))
            .position(x: frame.midX, y: frame.midY)
        }
    }

    /// Shown while a region is selected. The three actions are the selection chrome.
    /// They run on the button, not on a timer.
    @ViewBuilder
    private var regionToolbar: some View {
        if let id = keyboard.selectedRegionID,
           let region = document.region(id) {
            let rect = camera.viewport.viewRect(fromCanvas: region.bounds)
            HStack(spacing: 4) {
                Button {
                    performRegionAction {
                        _ = keyboard.setRegionAspectLocked(!region.aspectLocked, id: id, document: &document)
                    }
                } label: {
                    Text(verbatim: text("锁定"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderless)
                .background {
                    if region.aspectLocked {
                        Color.accentColor.opacity(0.22)
                    }
                }
                .clipShape(Capsule())
                .accessibilityIdentifier("region.lock")
                .accessibilityAddTraits(region.aspectLocked ? .isSelected : AccessibilityTraits())
                .help(Text(verbatim: text("锁定专区的宽高比")))
                Button {
                    performRegionAction {
                        _ = keyboard.fitRegion(id, frames: placedFrames(), document: &document)
                    }
                } label: {
                    Text(verbatim: text("适应"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("region.fit")
                .help(Text(verbatim: text("按当前圈住的节点调整专区")))
                Button {
                    performRegionAction {
                        _ = keyboard.makeRegionCircle(id, document: &document)
                    }
                } label: {
                    Text(verbatim: text("圆形"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("region.circle")
                .help(Text(verbatim: text("把专区变成圆形")))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .appleGlassChrome(.bottomBarCapsule)
            .position(x: rect.midX, y: max(18, rect.minY - 22))
        }
    }

    @ViewBuilder
    private var regionEditor: some View {
        if keyboard.mode == .edit,
           keyboard.editingRegionID != nil,
           let frame = regionEditFrame() {
            NodeTextEditor(
                text: Binding(
                    get: { keyboard.editingText },
                    set: { keyboard.replaceEditingText($0, document: &document) }
                ),
                isComposing: $keyboard.isComposing,
                minimumWidth: $compositionWidth,
                fontSize: CanvasTextScale.onScreenPointSize(fontSize: 14, scale: camera.viewport.scale),
                onEvent: { handleKey($0) },
                paper: colorScheme == .dark ? Color(white: 0.16) : Color.white,
                ink: colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16),
                dictationToken: dictationToken,
                dictationReplacesPlaceholder: dictationReplacesPlaceholder
            )
            .frame(width: max(frame.width, compositionWidth, 88), height: max(frame.height, 28))
            .position(x: frame.midX, y: frame.midY)
        }
    }

    private func performRegionAction(_ body: () -> Void) {
        if keyboard.mode == .edit, !keyboard.isComposing {
            keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
        }
        body()
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    private func stickyChromeContains(_ viewPoint: CGPoint) -> Bool {
        guard keyboard.mode == .command,
              let id = keyboard.selectedStickyID,
              let sticky = document.stickies.first(where: { $0.id == id }) else { return false }
        let rect = camera.viewport.viewRect(fromCanvas: CanvasPlacement.stickyCanvasRect(sticky))
        let chrome = CGRect(x: rect.midX - 70, y: max(0, rect.minY - 34), width: 140, height: 32)
        return chrome.contains(viewPoint)
    }

    private func regionToolbarContains(_ viewPoint: CGPoint) -> Bool {
        guard let id = keyboard.selectedRegionID,
              let region = document.region(id) else { return false }
        let rect = camera.viewport.viewRect(fromCanvas: region.bounds)
        let chrome = CGRect(x: rect.midX - 92, y: max(0, rect.minY - 40), width: 184, height: 36)
        return chrome.contains(viewPoint)
    }

    private func regionHit(at point: CGPoint) -> UUID? {
        switch CanvasRegionGeometry.hit(x: Double(point.x), y: Double(point.y), in: document.regions) {
        case .body(let id), .resize(let id):
            return id
        case nil:
            return nil
        }
    }

    private func beginRegionDrag(at start: CGPoint) -> RegionDrag? {
        guard let hit = CanvasRegionGeometry.hit(x: Double(start.x), y: Double(start.y), in: document.regions) else {
            return nil
        }
        let id: UUID
        let resizing: Bool
        switch hit {
        case .body(let bodyID):
            id = bodyID
            resizing = false
        case .resize(let resizeID):
            id = resizeID
            resizing = keyboard.selectedRegionID == resizeID
        }
        if !resizing, CanvasPlacement.nodeID(at: start, in: layoutSource()) != nil {
            return nil
        }
        guard let region = document.region(id) else { return nil }
        keyboard.beginRegionChange(document: document)
        keyboard.selectedRegionID = id
        interaction.selectedNodeID = nil
        return RegionDrag(
            id: id,
            resizing: resizing,
            originX: region.origin.x,
            originY: region.origin.y,
            width: region.width,
            height: region.height,
            locked: region.aspectLocked,
            startX: Double(start.x),
            startY: Double(start.y)
        )
    }

    private func updateRegionDrag(_ drag: RegionDrag, to point: CGPoint) {
        let dx = Double(point.x) - drag.startX
        let dy = Double(point.y) - drag.startY
        if drag.resizing {
            let size = CanvasRegionGeometry.resized(
                width: drag.width,
                height: drag.height,
                dx: dx,
                dy: dy,
                locked: drag.locked
            )
            _ = document.placeRegion(
                drag.id,
                origin: MindMapPoint(x: drag.originX, y: drag.originY),
                width: size.width,
                height: size.height
            )
        } else {
            _ = document.moveRegion(
                drag.id,
                to: MindMapPoint(x: drag.originX + dx, y: drag.originY + dy)
            )
        }
    }

    private func regionEditFrame() -> CGRect? {
        guard let id = keyboard.selectedRegionID, let region = document.region(id) else { return nil }
        let rect = camera.viewport.viewRect(fromCanvas: region.bounds)
        let height = max(28, min(36, rect.height * 0.45))
        let width = max(88, min(max(rect.width - 16, 88), max(compositionWidth, 220)))
        return CGRect(x: rect.minX + 8, y: rect.minY + 8, width: width, height: height)
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
        if keyboard.mode == .edit, keyboard.selectedRegionID != nil, let frame = regionEditFrame() {
            return frame
        }
        guard keyboard.mode == .edit,
              let id = keyboard.selectedNodeID,
              let frame = placedFrames().first(where: { $0.id == id }) else { return nil }
        let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
        return NodeEditChrome.editorFrame(node: rect, compositionWidth: compositionWidth)
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

    /// The color scheme's paper, or the system background when the map has no scheme.
    private var resolvedAppearance: LayoutAppearance {
        MapThemeCatalog.appearance(
            themeID: document.themeID,
            scheme: branchScheme,
            fallback: .standard
        )
    }

    @ViewBuilder
    private var audioPlaybackOverlay: some View {
        if let audioPlayer, let audioNodeID,
           let node = placedFrames().first(where: { $0.id == audioNodeID }) {
            let center = camera.viewport.viewPoint(fromCanvas: CGPoint(
                x: node.origin.x + node.size.width / 2,
                y: node.origin.y + node.size.height - 12
            ))
            CanvasAudioPlaybackBar(player: audioPlayer, onClose: onDismissAudio)
                .frame(width: min(280, max(180, node.size.width)))
                .position(center)
        }
    }

    @ViewBuilder
    private var paperLayer: some View {
        if let paper = resolvedAppearance.canvasBackground {
            Rectangle().fill(color(paper))
        } else {
            Rectangle().fill(.background)
        }
    }

    private var paperIsDark: Bool {
        guard let paper = resolvedAppearance.canvasBackground else {
            return colorScheme == .dark
        }
        let luminance = 0.2126 * paper.red + 0.7152 * paper.green + 0.0722 * paper.blue
        return luminance < 0.4
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
                if drag == nil && panAnchor == nil && stickyDrag == nil && regionDrag == nil && !ignoreDrag {
                    let start = camera.viewport.canvasPoint(fromView: value.startLocation)
                    if keyboard.mode == .edit, let frame = editFieldFrame(), frame.contains(value.startLocation) {
                        ignoreDrag = true
                        return
                    }
                    let onEditedSticky = keyboard.mode == .edit
                        && stickyHit(at: start) != nil
                        && stickyHit(at: start) == keyboard.selectedStickyID
                    let onEditedRegion = keyboard.mode == .edit
                        && regionHit(at: start) != nil
                        && regionHit(at: start) == keyboard.selectedRegionID
                    if stickyChromeContains(value.startLocation) || regionToolbarContains(value.startLocation) || onEditedSticky || onEditedRegion {
                        ignoreDrag = true
                    } else if persistsPlacement, keyboard.mode != .edit, let claim = beginStickyDrag(at: start) {
                        stickyDrag = claim
                    } else if persistsPlacement, keyboard.mode != .edit, let claim = beginRegionDrag(at: start) {
                        regionDrag = claim
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
                } else if let regionDrag {
                    let point = camera.viewport.canvasPoint(fromView: value.location)
                    updateRegionDrag(regionDrag, to: point)
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
                if regionDrag != nil {
                    keyboard.commitRegionChange(document: document)
                }
                drag = nil
                stickyDrag = nil
                regionDrag = nil
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

    private func draw(in context: GraphicsContext, size: CGSize, at time: TimeInterval) {
        drawGrid(in: context, size: size)
        // The open petal starts from a bud. Don't paint the settled tree for one frame first.
        if !petalMapOpened && !reduceMotion { return }
        let placed = placedFrames()
        let blooming = petal.isActive(at: time)
        let boundaryMarks = !blooming && document.hasBoundaries
            ? SummaryGeometry.boundaries(in: document, frames: placed)
            : []
        let summaryMarks = !blooming && document.hasSummaries
            ? SummaryGeometry.summaries(in: document, frames: placed)
            : []
        let scale = camera.viewport.scale
        if !document.regions.isEmpty {
            let regionViewport = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for region in document.regions {
                let box = camera.viewport.viewRect(fromCanvas: region.bounds)
                guard box.intersects(regionViewport) else { continue }
                draw(region, in: box, scale: scale, context: context)
            }
        }
        if !boundaryMarks.isEmpty {
            let viewBounds = CGRect(origin: .zero, size: size).insetBy(dx: -48, dy: -48)
            for mark in boundaryMarks {
                let box = camera.viewport.viewRect(fromCanvas: mark.bounds)
                guard box.intersects(viewBounds) else { continue }
                drawBoundary(mark, scale: scale, in: context)
            }
        }
        let viewport = camera.viewport.canvasRect(in: size).insetBy(dx: -48, dy: -48)
        var visible = CanvasPlacement.frames(placed, intersectingCanvas: viewport)
        let linkIDs = CanvasPlacement.nodeIDsWithVisibleLinks(placed, viewport: viewport)
        let ghosts: [PetalGhost]
        if blooming {
            let visibleIDs = Set(visible.map(\.id))
            for node in placed where !visibleIDs.contains(node.id) {
                guard let pose = petal.pose(for: node.id, at: time), pose.draws else { continue }
                visible.append(node)
            }
            for node in placed {
                guard let link = node.link else { continue }
                if petal.hides(node.id, at: time) { continue }
                let pose = petal.pose(for: node.id, at: time)
                if let pose, !pose.draws { continue }
                if pose == nil && !linkIDs.contains(node.id) { continue }
                let curve = pose.map { PetalExpandGeometry.grow(link, from: $0.origin, growth: $0.growth) } ?? link
                stroke(
                    curve,
                    straight: CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                    opacity: pose?.opacity ?? 1,
                    in: context
                )
            }
            ghosts = petal.ghosts(at: time)
            for ghost in ghosts {
                guard let link = ghost.frame.link else { continue }
                let curve = PetalExpandGeometry.grow(link, from: ghost.pose.origin, growth: ghost.pose.growth)
                stroke(
                    curve,
                    straight: CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                    opacity: ghost.pose.opacity,
                    in: context
                )
            }
        } else {
            ghosts = []
            for node in placed where linkIDs.contains(node.id) {
                guard let link = node.link else { continue }
                stroke(
                    link,
                    straight: CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                    in: context
                )
            }
        }
        let relationships = blooming ? [] : relationshipLines(in: placed)
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
            let pose: PetalPose?
            if blooming {
                if petal.hides(node.id, at: time) { continue }
                pose = petal.pose(for: node.id, at: time)
                if let pose, !pose.draws { continue }
            } else {
                pose = nil
            }
            let onScreen = min(node.size.width, node.size.height) * scale * (pose?.scale ?? 1)
            let highlighted = tagFilter.isActive && highlightedIDs.contains(node.id)
            let dimmed = tagFilter.isActive && !highlighted && interaction.selectedNodeID != node.id
            draw(
                node,
                detail: CanvasDetail.level(scale: scale, onScreenHeight: onScreen),
                scale: scale,
                highlighted: highlighted,
                dimmed: dimmed,
                pose: pose,
                in: context
            )
        }
        for ghost in ghosts {
            let onScreen = min(ghost.frame.size.width, ghost.frame.size.height) * scale * ghost.pose.scale
            draw(
                ghost.frame,
                detail: CanvasDetail.level(scale: scale, onScreenHeight: onScreen),
                scale: scale,
                highlighted: false,
                dimmed: false,
                pose: ghost.pose,
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

    private func stroke(_ link: LinkCurve, straight: Bool, opacity: Double = 1, in context: GraphicsContext) {
        let drawn = ThemeCurvePath.make(link: link, straight: straight) { point in
            camera.viewport.viewPoint(fromCanvas: point)
        }
        let ink = color(link.color).opacity(opacity)
        if drawn.tapered {
            context.fill(drawn.path, with: .color(ink))
        } else {
            context.stroke(drawn.path, with: .color(ink), lineWidth: link.lineWidth)
        }
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

    private func draw(_ region: CanvasRegion, in rect: CGRect, scale: CGFloat, context: GraphicsContext) {
        guard rect.width > 1, rect.height > 1 else { return }
        let path = regionPath(rect, shape: region.shape)
        context.fill(path, with: .color(color(region.fill)))
        if region.strokeWidth > 0 {
            let width = max(CGFloat(region.strokeWidth) * scale, 0.5)
            context.stroke(path, with: .color(color(region.border)), lineWidth: width)
        }
        let selected = keyboard.selectedRegionID == region.id
        if selected {
            context.stroke(path, with: .color(color(interaction.selectionBorder)), lineWidth: 1.5)
        }
        let editing = keyboard.editingRegionID == region.id
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: 14, scale: scale)
        if !editing, CanvasTextLOD.level(onScreenPointSize: pointSize).drawsTitle, !region.label.isEmpty {
            let insetX = 12 * max(scale, 0.5)
            let insetY = 8 * max(scale, 0.5)
            let band = CGRect(
                x: rect.minX + insetX,
                y: rect.minY + insetY,
                width: max(0, rect.width - insetX * 2),
                height: min(max(0, rect.height - insetY * 2), pointSize + 6)
            )
            if band.width > 1, band.height > 1 {
                var layer = context
                layer.clip(to: path)
                layer.draw(
                    Text(region.label)
                        .font(.system(size: pointSize))
                        .foregroundStyle(regionLabelInk(region.fill)),
                    in: band
                )
            }
        }
        if selected, keyboard.mode == .command {
            let handle = CGRect(x: rect.maxX - 10, y: rect.maxY - 10, width: 7, height: 7)
            context.fill(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(color(interaction.selectionBorder)))
        }
    }

    private func regionPath(_ rect: CGRect, shape: CanvasRegionShape) -> Path {
        switch shape {
        case .rectangle:
            return Path(roundedRect: rect, cornerRadius: min(10, rect.height / 6))
        case .ellipse:
            return Path(ellipseIn: rect)
        }
    }

    private func regionLabelInk(_ fill: BranchColor) -> Color {
        let luma = 0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue
        if luma > 0.62 {
            return Color(red: 0.12, green: 0.14, blue: 0.16)
        }
        return .white
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
        pose: PetalPose? = nil,
        in context: GraphicsContext
    ) {
        let rect = camera.viewport.viewRect(fromCanvas: posedCanvasRect(node, pose: pose))
        let normalRadius: CGFloat = detail == .far ? min(node.cornerRadius, 4) : node.cornerRadius
        let radius: CGFloat
        if let pose {
            let circle = min(rect.width, rect.height) / 2
            let mix = CGFloat(pose.cornerCircle)
            radius = circle * mix + normalRadius * (1 - mix)
        } else {
            radius = normalRadius
        }
        let path = Path(roundedRect: rect, cornerRadius: radius)
        let selected = interaction.selectedNodeID == node.id
        var layer = context
        var opacity = pose?.opacity ?? 1
        if dimmed { opacity *= TopicTagCanvas.dimOpacity }
        if opacity < 0.999 { layer.opacity = opacity }
        let editing = keyboard.mode == .edit && selected
        if !node.hidesFill {
            if pose == nil, detail.drawsShadow {
                var shadowed = layer
                shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5))
                shadowed.fill(path, with: .color(color(node.fill)))
            } else {
                layer.fill(path, with: .color(color(node.fill)))
            }
        }
        if !editing, detail != .far, selected {
            layer.stroke(
                path,
                with: .color(color(interaction.selectionBorder)),
                lineWidth: interaction.selectionBorderWidth
            )
        } else if !editing, detail.drawsFineBorder || (detail == .mid && node.borderWidth >= 2.5) {
            if node.borderWidth > 0 {
                layer.stroke(path, with: .color(color(node.border)), lineWidth: node.borderWidth)
            }
        }
        if highlighted, detail != .far {
            context.stroke(path, with: .color(color(TopicTagCanvas.highlight)), lineWidth: 2.5)
        }
        if pose == nil, selected, detail.drawsSelectionHandles, NodeEditChrome.showsSelectionHandles(editing: editing) {
            drawHandles(around: rect, in: context)
        }
        var textRect = rect.insetBy(dx: 6, dy: 4)
        if pose == nil,
           detail != .far,
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
        if pose == nil, detail.drawsText, let first = node.fileBadges.first {
            let badgeTop = camera.viewport.viewPoint(fromCanvas: CGPoint(
                x: node.origin.x,
                y: node.origin.y + CGFloat(first.row.y)
            )).y
            textRect.size.height = max(0, min(textRect.maxY, badgeTop - 2) - textRect.minY)
        }
        if pose == nil, detail.drawsText, node.tagBandHeight > 0 {
            let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: node.fileBadges.count))
            let tagTop = node.origin.y + node.size.height - fileBand - node.tagBandHeight
            let tagY = camera.viewport.viewPoint(fromCanvas: CGPoint(x: node.origin.x, y: tagTop)).y
            textRect.size.height = max(0, min(textRect.maxY, tagY - 2) - textRect.minY)
        }
        let pointSize = CanvasTextScale.onScreenPointSize(fontSize: node.fontSize, scale: scale)
        textRect = excludingChildBadge(textRect, node: node, scale: scale)
        let showTitle = (pose?.showsText ?? true) && !editing
        if showTitle, CanvasTextLOD.level(onScreenPointSize: pointSize).drawsTitle, textRect.height > 1, textRect.width > 1 {
            let text = styledText(node, pointSize: pointSize)
            var textLayer = layer
            textLayer.clip(to: Path(textRect))
            textLayer.draw(text, at: CGPoint(x: textRect.midX, y: textRect.midY), anchor: .center)
        }
        if pose == nil, detail.drawsText {
            drawFileBadges(node, scale: scale, pointSize: pointSize, in: layer)
            TopicTagCanvas.draw(node: node, in: rect, context: layer, color: color, ink: color(node.textColor))
        }
    }

    private func posedCanvasRect(_ node: NodeFrame, pose: PetalPose?) -> CGRect {
        guard let pose, pose.draws else { return node.frame }
        let width = node.size.width * pose.scale
        let height = node.size.height * pose.scale
        return CGRect(x: pose.center.x - width / 2, y: pose.center.y - height / 2, width: width, height: height)
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
            .font(FlorettaTitleFont.font(design: node.fontDesign, size: pointSize))
            .foregroundStyle(color(node.textColor))
        if node.bold { text = text.bold() }
        if node.italic { text = text.italic() }
        if node.strikethrough { text = text.strikethrough() }
        if node.underline { text = text.underline() }
        return text
    }

    private func excludingChildBadge(_ textRect: CGRect, node: NodeFrame, scale: CGFloat) -> CGRect {
        let badge = node.childBadgeInset * scale
        guard badge > 0, textRect.width > 0 else { return textRect }
        var rect = textRect
        if node.childBadgeOnMinX {
            rect.origin.x += badge
        }
        rect.size.width = max(0, rect.width - badge)
        return rect
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
        let tile = dotTiles.image(step: layout.step, scheme: paperIsDark ? .dark : .light)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .tiledImage(tile, origin: layout.tileOrigin, scale: 1)
        )
    }

}

/// Full-size accessibility box for the idle topic. A text glyph collapses to one pixel,
/// so XCUI would compare that sliver with the editing field.
private struct NodeChromeProbeBox: View {
    var value: String

    var body: some View {
        #if os(macOS)
        MacNodeChromeProbe(value: value)
        #else
        IOSNodeChromeProbe(value: value)
        #endif
    }
}

#if os(macOS)
private struct MacNodeChromeProbe: NSViewRepresentable {
    var value: String

    func makeNSView(context: Context) -> NodeChromeProbeNSView {
        let view = NodeChromeProbeNSView()
        view.probeValue = value
        return view
    }

    func updateNSView(_ nsView: NodeChromeProbeNSView, context: Context) {
        nsView.probeValue = value
        nsView.publish()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NodeChromeProbeNSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.bounds.width, height: proposal.height ?? nsView.bounds.height)
    }
}

private final class NodeChromeProbeNSView: NSView {
    var probeValue = "" {
        didSet { publish() }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        publish()
    }

    func publish() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        setAccessibilityElement(true)
        setAccessibilityIdentifier(NodeEditChrome.accessibilityIdentifier)
        setAccessibilityLabel("node")
        if accessibilityValue() as? String != probeValue {
            setAccessibilityValue(probeValue)
        }
        guard let window else { return }
        setAccessibilityFrame(window.convertToScreen(convert(bounds, to: nil)))
    }
}
#else
private struct IOSNodeChromeProbe: UIViewRepresentable {
    var value: String

    func makeUIView(context: Context) -> NodeChromeProbeUIView {
        let view = NodeChromeProbeUIView()
        view.probeValue = value
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: NodeChromeProbeUIView, context: Context) {
        uiView.probeValue = value
        uiView.publish()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NodeChromeProbeUIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
}

private final class NodeChromeProbeUIView: UIView {
    var probeValue = "" {
        didSet { publish() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    func publish() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        isAccessibilityElement = true
        accessibilityIdentifier = NodeEditChrome.accessibilityIdentifier
        accessibilityLabel = "node"
        if (accessibilityValue as? String) != probeValue {
            accessibilityValue = probeValue
        }
        accessibilityFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
    }
}
#endif

/// How a topic looks while its text field is open.
/// The field keeps the node's fill, type, and frame. One accent stroke is added.
/// Marked text may widen the field; a line that already fits does not.
enum NodeEditChrome {
    static let accessibilityIdentifier = "canvas.node.chrome"
    /// Solid selection stroke. System accent, same corner radius as the node.
    static let selectionStrokeWidth: CGFloat = 2
    /// Matches the canvas title clip (`insetBy(dx: 6, dy: 4)`) so glyphs do not jump.
    static let textInset = CGSize(width: 6, height: 4)

    static func showsSelectionHandles(editing: Bool) -> Bool {
        !editing
    }

    /// Same origin and size as `node` until marked text is wider than the topic.
    static func editorFrame(node: CGRect, compositionWidth: CGFloat) -> CGRect {
        let extra = compositionWidth.isFinite ? compositionWidth : 0
        let width = extra > node.width ? extra : node.width
        return CGRect(x: node.midX - width / 2, y: node.minY, width: width, height: node.height)
    }

    static func hex(_ color: BranchColor) -> String {
        func byte(_ channel: Double) -> Int {
            Int((min(max(channel, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }

    static func accessibilityValue(editing: Bool, fill: BranchColor, size: CGSize) -> String {
        let mode = editing ? "edit" : "idle"
        let width = String(format: "%.2f", Double(size.width))
        let height = String(format: "%.2f", Double(size.height))
        return "mode=\(mode);fill=\(hex(fill));w=\(width);h=\(height)"
    }

    static func fillHex(in value: String) -> String? {
        token("fill", in: value)
    }

    static func mode(in value: String) -> String? {
        token("mode", in: value)
    }

    static func size(in value: String) -> CGSize? {
        guard let width = token("w", in: value).flatMap(Double.init),
              let height = token("h", in: value).flatMap(Double.init) else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func token(_ key: String, in value: String) -> String? {
        for part in value.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2, pieces[0] == key { return pieces[1] }
        }
        return nil
    }

    /// One burgundy topic, short enough that the old 88×36 edit field would grow it.
    static func sampleDocument() -> MindMapDocument {
        let node = MindMapNode(
            text: "样式",
            style: MindMapNodeStyle(
                colorHex: "#800020",
                fillHex: "#800020",
                borderHex: "#4A1020",
                textHex: "#FFFFFF",
                fontSize: 20,
                borderWidth: 2,
                cornerRadius: 12,
                fontDesign: "rounded"
            ),
            position: MindMapPoint(x: 64, y: 96)
        )
        return MindMapDocument(title: "样式", roots: [node])
    }
}

/// Colors and type the editing text view paints. The canvas still owns the shape.
struct NodeEditSurface: Equatable {
    var fill: BranchColor
    var textColor: BranchColor
    var hidesFill: Bool
    var cornerRadius: CGFloat
    var fontSize: CGFloat
    var fontDesign: String
    var bold: Bool
    var italic: Bool
    var strikethrough: Bool
    var underline: Bool
}

/// Taps that land on the system text field must not commit or close it.
/// Marked text can make the field wider than the topic. The node hit-test misses that margin.
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

private struct RegionDrag {
    var id: UUID
    var resizing: Bool
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double
    var locked: Bool
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
    /// Increments only when the cache misses. Petal playback must not move this.
    private(set) var layoutPassCount = 0

    func frames(for document: MindMapDocument, scheme: MapColorScheme) -> [NodeFrame] {
        if let source, source == document, cachedScheme == scheme { return cached }
        layoutPassCount += 1
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
                  AttachmentKind.isImageExtension(ext) || ext == "mp4" || ext == "mov" else { continue }
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
        if let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension, ext == "mp4" || ext == "mov" {
            return produceVideoThumbnail(
                entry: entry,
                hash: entry.sha256 ?? "",
                cache: cache,
                archiveURL: archiveURL,
                spillDirectory: spillDirectory
            )
        }
        return try? ThumbnailPipeline.materialize(
            entry: entry,
            archiveURL: archiveURL,
            spillDirectory: spillDirectory,
            cache: cache,
            decoder: ImageIOThumbnailDecoder(),
            files: FoundationStreamingFiles()
        )
    }

    nonisolated private static func produceVideoThumbnail(
        entry: ZipStoredEntry,
        hash: String,
        cache: ThumbnailFileCache,
        archiveURL: URL,
        spillDirectory: URL
    ) -> Data? {
        let url = spillDirectory.appendingPathComponent("\(UUID().uuidString).\(AttachmentNames.parseAsset(entry.name)?.fileExtension ?? "mov")")
        do {
            try FileManager.default.createDirectory(at: spillDirectory, withIntermediateDirectories: true)
            try FilePreviewSpill.write(entry: entry, archiveURL: archiveURL, to: url, files: FoundationStreamingFiles())
            defer { try? FileManager.default.removeItem(at: url) }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: StreamingBudget.thumbnailLongestEdge, height: StreamingBudget.thumbnailLongestEdge)
            let frame = try generator.copyCGImage(at: .zero, actualTime: nil)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, frame, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            let bytes = data as Data
            try cache.store(bytes, for: hash)
            return bytes
        } catch {
            return nil
        }
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

    func restore(_ state: CanvasViewportState) {
        var updated = viewport
        updated.restore(state)
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
