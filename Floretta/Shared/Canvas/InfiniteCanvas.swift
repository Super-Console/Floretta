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
    /// Pending clear for the hovered topic. The add handles sit outside the topic
    /// box, so a pointer that steps off the box is usually on its way to a handle.
    @State private var hoverClearTask: Task<Void, Never>?
    @State private var panAnchor: CGPoint?
    /// The marquee in flight. Non-nil while the user drags on blank paper in
    /// pointer mode; the selection updates live and Escape puts it back.
    @State private var marquee: CanvasMarqueeState?
    /// Space borrows the hand. The tap / hold decision is made on key up.
    @State private var spaceGesture = CanvasSpaceGesture()
    @State private var spaceHeld = false
    #if os(macOS)
    /// True while the pointer is over the canvas, so a pushed cursor is only
    /// ever on the stack where it belongs.
    @State private var hoveringCanvas = false
    /// The one cursor of ours on the stack. Nil when we have pushed nothing.
    @State private var pushedCursor: CanvasCursorKind?
    #endif
    @State private var pinchStartScale: CGFloat?
    @State private var interaction = CanvasInteraction.standard
    @Binding var keyboard: MindMapKeyboardSession
    var camera: CanvasCamera
    var clock: any ClockPort
    var fontMetrics: any FontMetricsPort = CoreTextFontMetrics()
    var focusNodeID: UUID? = nil
    var zenActive: Bool = false
    /// Pointer (marquee on blank paper) or hand (pan on blank paper). The Mac
    /// opens as a pointer; iPhone and iPad always run as the hand, so their
    /// drags are the ones they already had.
    var pointerMode: CanvasPointerMode = CanvasPointerMode.platformDefault
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
    var onChromeCommand: (MindMapCommand) -> Void = { _ in }
    @State private var compositionWidth: CGFloat = 0
    @State private var keyCoalescer = KeyDeliveryCoalescer()
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
    @Environment(\.appearanceProfile) private var appearanceProfile
    @AppStorage("floretta.language") private var storedInterfaceLanguage = AppLanguage.system.rawValue
    @FocusState private var canvasFocused: Bool

    var body: some View {
        KeyLatencyProbe.shared.timeBuild("canvas") {
            let _ = CanvasPerfRun.noteBody()
            let _ = KeyLatencyProbe.shared.countCanvasBody(signature: canvasBodySignature())
            return GeometryReader { geo in
                observeCanvas(canvasSurface(size: geo.size), size: geo.size)
            }
            .focusEffectDisabled(true)
        }
    }

    /// Diagnostic only: what each `body` pass saw. The key-latency run diffs
    /// consecutive lines to name the state that invalidated the canvas.
    private func canvasBodySignature() -> String {
        guard KeyLatencyProbe.isEnabled else { return "" }
        let sel = keyboard.selectedNodeID.map { $0.uuidString.prefix(4).lowercased() } ?? "-"
        let hov = interaction.hoveredNodeID.map { $0.uuidString.prefix(4).lowercased() } ?? "-"
        let scale = String(format: "%.3f", camera.viewport.scale)
        let offX = Int(camera.viewport.offset.x)
        let offY = Int(camera.viewport.offset.y)
        let boundsW = Int(camera.contentBounds?.width ?? 0)
        let boundsH = Int(camera.contentBounds?.height ?? 0)
        let mode = keyboard.mode == .edit ? "edit" : "cmd"
        let composing = keyboard.isComposing ? 1 : 0
        let playing = petal.isPlaying ? 1 : 0
        let topics = document.roots.count + document.freeNodes.count
        let live = camera.liveNodeOrigin == nil ? 0 : 1
        let width = Int(compositionWidth)
        let pass = laidOut.layoutPassCount
        return "mode=\(mode),comp=\(composing),sel=\(sel),hov=\(hov),scale=\(scale),off=\(offX):\(offY),bounds=\(boundsW)x\(boundsH),pass=\(pass),width=\(width),petal=\(playing),doc=\(topics),live=\(live)"
    }

    private func canvasSurface(size: CGSize) -> some View {
        canvasFocusSurface(canvasHoverSurface(canvasOverlaySurface(canvasGestureSurface(size: size))))
    }

    private func canvasGestureSurface(size: CGSize) -> some View {
        canvasVisuals
            .gesture(dragGesture)
            .simultaneousGesture(pinchGesture(in: size))
    }

    private func canvasOverlaySurface<V: View>(_ view: V) -> some View {
        canvasSecondaryOverlays(canvasPrimaryOverlays(view))
    }

    private func canvasPrimaryOverlays<V: View>(_ view: V) -> some View {
        view
        .overlay {
            CanvasScrollCatcher { delta, location, command in
                camera.viewport.applyScroll(delta: delta, around: location, command: command)
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            }
        }
        .overlay { if !zenActive { hoverAddButtons } }
        .overlay { editField }
        .overlay { nodeChromeProbe }
        .overlay { if !zenActive { stickyChrome } }
        .overlay { marqueeRect }
        .overlay(alignment: .topLeading) { heldCanvasScaleLabel }
    }

    private func canvasSecondaryOverlays<V: View>(_ view: V) -> some View {
        view
        .overlay { if !zenActive { stickyEditor } }
        .overlay { if !zenActive { regionToolbar } }
        .overlay { if !zenActive { regionEditor } }
        .overlay { if !zenActive { relationshipEditor } }
        .overlay { if !zenActive { summaryEditor } }
        .overlay { if !zenActive { boundaryEditor } }
        .overlay { if !zenActive { audioPlaybackOverlay } }
    }

    private func canvasHoverSurface<V: View>(_ view: V) -> some View {
        view
        .canvasHover { location in
            #if os(macOS)
            hoveringCanvas = location != nil
            syncPointerCursor()
            #endif
            guard let location else {
                scheduleHoverClear()
                return
            }
            let point = camera.viewport.canvasPoint(fromView: location)
            // The add handles are drawn outside the topic box, so the hit test has
            // to accept the ring around a topic or the handles vanish as soon as
            // the pointer starts towards one. `hoverInflate` is in view points and
            // the hit test runs in canvas space, so it is divided by the zoom.
            let inflate = AddHandleGeometry.canvasInflate(scale: camera.viewport.scale)
            guard let id = CanvasPlacement.nodeIDNear(at: point, inflate: inflate, in: layoutSource()) else {
                scheduleHoverClear()
                return
            }
            hoverClearTask?.cancel()
            hoverClearTask = nil
            if interaction.hoveredNodeID != id {
                interaction.hoveredNodeID = id
            }
        }
    }

    /// Holds a miss for `AddHandleGeometry.hoverGraceMilliseconds` before the
    /// hover clears, so crossing the gap between two handles does not blink them.
    /// Captures bindings, never `self`, so the task stays sendable.
    private func scheduleHoverClear() {
        guard interaction.hoveredNodeID != nil, hoverClearTask == nil else { return }
        let hovered = $interaction.hoveredNodeID
        let pending = $hoverClearTask
        hoverClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(AddHandleGeometry.hoverGraceMilliseconds))
            guard !Task.isCancelled else { return }
            pending.wrappedValue = nil
            hovered.wrappedValue = nil
        }
    }

    private func canvasFocusSurface<V: View>(_ view: V) -> some View {
        view
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
        let isPetalPlaying = petal.isPlaying
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPetalPlaying)) { timeline in
            Canvas { context, size in
                let perf = CanvasPerfRun.beginDraw()
                KeyLatencyProbe.shared.mark(.drawStarted)
                draw(in: context, size: size, at: timeline.date.timeIntervalSinceReferenceDate)
                KeyLatencyProbe.shared.mark(.drawEnded)
                CanvasPerfRun.endDraw(perf)
                KeyLatencyProbe.shared.noteDrawEnded()
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
            .background {
                #if os(iOS)
                HardwareShortcutHost(
                    mode: keyboard.mode,
                    isComposing: keyboard.isComposing,
                    isEnabled: canvasFocused,
                    coalescer: keyCoalescer,
                    bindings: keyboard.bindings,
                    onEvent: { handleKey($0) }
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                #endif
            }
            .onKeyPress(phases: [.down, .repeat, .up]) { press in
                // Key-latency probe: the two create keys open a timed press here,
                // before any dispatch, so the frame that shows the new topic can be
                // measured against the moment the key arrived.
                if KeyLatencyProbe.isEnabled, press.phase == .down, keyboard.mode == .command {
                    if press.key == .tab {
                        KeyLatencyProbe.shared.noteKeyPress(name: "tab")
                    } else if press.key == .return {
                        KeyLatencyProbe.shared.noteKeyPress(name: "enter")
                    }
                }
                // Escape with a marquee in flight puts back the selection the
                // drag started from, and must not also leave zen mode.
                if press.key == .escape, press.modifiers.isEmpty, marquee != nil {
                    cancelMarquee()
                    return .handled
                }
                if press.key == .escape, !keyboard.isComposing, onEscape() {
                    return .handled
                }
                #if os(macOS)
                // Space is two gestures at once: a hold borrows the hand, a tap
                // is still 编辑主题. The key down answers at once; the key up
                // decides. Auto-repeat is the same press, never a second tap.
                if press.key == .space, keyboard.mode == .command, !keyboard.isComposing {
                    if press.phase == .up {
                        return endSpaceHold() ? .handled : .ignored
                    }
                    guard press.modifiers.isEmpty else { return .ignored }
                    return beginSpaceHold() ? .handled : .ignored
                }
                #endif
                guard press.phase == .down else { return .ignored }
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
                if document.roots.count == 1,
                   let rootID = document.roots.first?.id,
                   let rootFrame = placedFrames().first(where: { $0.id == rootID }) {
                    // A single-root document always opens centered, even when it has a
                    // persisted pan. Defer until DocumentEditor's camera restoration has
                    // completed, then center without adding another state write.
                    Task { @MainActor in
                        await Task.yield()
                        guard document.roots.count == 1 else { return }
                        camera.centerOn(rootFrame.frame)
                    }
                }
                publishBounds()
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
                refreshThumbnails()
                openPetalMap()
                canvasFocused = true
                startPerfRunIfRequested()
                KeyLatencyDriver.startIfRequested()
                applyPendingHeldCanvasScale(in: size)
            }
            .background {
                if CanvasScaleHook.isEnabled {
                    HeldCanvasScaleTick {
                        applyPendingHeldCanvasScale(in: size)
                    }
                }
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
                    now: clock.now().timeIntervalSinceReferenceDate,
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
                    // A Space hold belongs to the command mode. Entering the
                    // editor drops it so the key goes back to typing spaces.
                    spaceGesture.reset()
                    spaceHeld = false
                    #if os(macOS)
                    syncPointerCursor()
                    #endif
                }
            }
            .onChange(of: pointerMode) { _, _ in
                #if os(macOS)
                syncPointerCursor()
                #endif
            }
            .onChange(of: keyboard.selectedNodeID) { _, id in
                interaction.selectedNodeID = id
            }
            .onDisappear {
                #if os(macOS)
                hoveringCanvas = false
                syncPointerCursor()
                #endif
                spaceGesture.reset()
                spaceHeld = false
                marquee = nil
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
            let location = value.location
            DispatchQueue.main.async {
                handleCanvasDoubleTap(at: location)
            }
        }
    }

    /// Let AppKit finish the double-click gesture/layout transaction before the
    /// editor or document state changes invalidate the toolbar's preferences.
    private func handleCanvasDoubleTap(at location: CGPoint) {
        if EditFieldGuard.ignoresCanvasTap(
            at: location,
            editFrame: editFieldFrame(),
            isComposing: keyboard.isComposing
        ) { return }
        let point = camera.viewport.canvasPoint(fromView: location)
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
            if id != nil, keyboard.mode == .command {
                canvasFocused = true
            }
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
            now: clock.now().timeIntervalSinceReferenceDate,
            layoutPassCount: laidOut.layoutPassCount
        )
        petalMapOpened = true
    }

    private func publishBounds() {
        KeyLatencyProbe.shared.countBoundsPublish()
        camera.contentBounds = CanvasPlacement.contentBounds(
            in: layoutSource(),
            scheme: branchScheme,
            profile: appearanceProfile
        )
    }

    @ViewBuilder
    private var hoverAddButtons: some View {
        if let id = interaction.hoveredNodeID,
           !document.isInFreeNodeTree(id),
           let frame = placedFrames().first(where: { $0.id == id }) {
            let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
            // Only the directions this structure can grow in. A logic chart has no
            // left branch, and a top-down chart has no horizontal one.
            ForEach(document.layoutKind.addDirections, id: \.self) { direction in
                addButton(
                    direction,
                    at: AddHandleGeometry.handleCenter(direction, in: rect),
                    parent: id
                )
            }
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
                fontMetrics: fontMetrics,
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
                    underline: frame.underline,
                    textAlignment: frame.textAlignment
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

    /// Test-only geometry/color signal on a separate, non-text accessibility element.
    @ViewBuilder
    private var nodeChromeProbe: some View {
        if let id = keyboard.selectedNodeID,
           let frame = placedFrames().first(where: { $0.id == id }) {
            let editing = keyboard.mode == .edit
            let rect = camera.viewport.viewRect(fromCanvas: frame.frame)
            let bounds = editing
                ? NodeEditChrome.editorFrame(node: rect, compositionWidth: compositionWidth)
                : rect
            NodeChromeProbeBox(
                identifier: NodeEditChrome.probeIdentifier(editing: editing, fill: frame.fill)
            )
            .frame(width: bounds.width, height: bounds.height)
            .position(x: bounds.midX, y: bounds.midY)
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
                fontMetrics: fontMetrics,
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
                fontMetrics: fontMetrics,
                onEvent: { handleKey($0) },
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
                fontMetrics: fontMetrics,
                onEvent: { handleKey($0) },
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
                fontMetrics: fontMetrics,
                onEvent: { handleKey($0) },
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
                fontMetrics: fontMetrics,
                onEvent: { handleKey($0) },
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
        let frames = laidOut.frames(for: layoutSource(), scheme: branchScheme, profile: appearanceProfile)
        guard let live = camera.liveNodeOrigin else { return frames }
        return CanvasPlacement.applyingLiveOrigin(frames, id: live.id, origin: live.origin)
    }

    private var branchScheme: MapColorScheme {
        colorScheme == .dark ? .dark : .light
    }

    /// The paper this document draws on. Its own stored color wins; a file that
    /// never stored one keeps the appearance default, so old files stay put.
    private var resolvedAppearance: LayoutAppearance {
        var resolved = appearanceProfile.applying(
            to: MapThemeCatalog.appearance(
                themeID: document.themeID,
                scheme: branchScheme,
                fallback: .standard
            ),
            scheme: branchScheme
        )
        resolved.canvasBackground = document.resolvedCanvasBackground(fallback: resolved.canvasBackground)
        return resolved
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
        let handled = MindMapKeyDispatch.handle(
            event,
            keyboard: &keyboard,
            document: &document,
            frames: placedFrames(),
            coalescer: keyCoalescer
        ) { command in
            handleChrome(command)
        }
        KeyLatencyProbe.shared.mark(.modelApplied)
        interaction.selectedNodeID = keyboard.selectedNodeID
        return handled
    }

    private func handleChrome(_ command: MindMapCommand) {
        switch command {
        case .jumpToCentralTopic:
            if let id = keyboard.selectedNodeID,
               let frame = placedFrames().first(where: { $0.id == id }) {
                camera.centerOn(frame.frame)
            }
        default:
            onChromeCommand(command)
        }
    }

    private func addButton(_ direction: CanvasDirection, at point: CGPoint, parent: UUID) -> some View {
        Button {
            // A handle is a create-then-type gesture: the new topic opens in its
            // editor, which is what Tab does from the keyboard. Text typed on the
            // previous topic is committed first so it is not written to the new one.
            if keyboard.mode == .edit {
                keyboard.apply(.commitEdit, document: &document, frames: placedFrames())
            }
            guard let childID = CanvasCommands.apply(
                .addChild(parentID: parent, direction: direction),
                document: &document,
                interaction: &interaction
            ) else { return }
            beginEditing(childID)
        } label: {
            // The glyph stays inside `buttonSide`, which is what keeps the whole
            // handle within the hover ring `AddHandleGeometry.hoverInflate` allows.
            Image(systemName: "plus.circle.fill")
                .font(.system(size: AddHandleGeometry.buttonSide * 0.75))
                .frame(width: AddHandleGeometry.buttonSide, height: AddHandleGeometry.buttonSide)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .position(point)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag == nil && panAnchor == nil && stickyDrag == nil && regionDrag == nil
                    && marquee == nil && !ignoreDrag {
                    beginDrag(at: value.startLocation)
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
                    camera.liveNodeOrigin = (drag.id, origin)
                } else if marquee != nil {
                    updateMarquee(to: camera.viewport.canvasPoint(fromView: value.location))
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
                if let live = camera.liveNodeOrigin {
                    camera.liveNodeOrigin = nil
                    document = CanvasPlacement.movingNode(live.id, to: live.origin, in: document)
                }
                drag = nil
                stickyDrag = nil
                regionDrag = nil
                panAnchor = nil
                ignoreDrag = false
                // The marquee ends where it let go; the selection it produced
                // stays. Escape is the only way to put the old set back.
                marquee = nil
                #if os(macOS)
                syncPointerCursor()
                #endif
            }
    }

    /// One press, one intent.
    ///
    /// Order matters and is the same one the canvas always had: chrome that runs
    /// its own interaction, then a sticky, then a region, then a topic. Only
    /// blank paper is left for the pointer mode to decide, and `CanvasPointerRouter`
    /// makes that call so the rule is testable without a window.
    private func beginDrag(at startLocation: CGPoint) {
        let start = camera.viewport.canvasPoint(fromView: startLocation)
        if keyboard.mode == .edit, let frame = editFieldFrame(), frame.contains(startLocation) {
            ignoreDrag = true
            return
        }
        let onEditedSticky = keyboard.mode == .edit
            && stickyHit(at: start) != nil
            && stickyHit(at: start) == keyboard.selectedStickyID
        let onEditedRegion = keyboard.mode == .edit
            && regionHit(at: start) != nil
            && regionHit(at: start) == keyboard.selectedRegionID
        let onChrome = stickyChromeContains(startLocation)
            || regionToolbarContains(startLocation)
            || onEditedSticky
            || onEditedRegion
        if !onChrome, persistsPlacement, keyboard.mode != .edit, let claim = beginStickyDrag(at: start) {
            stickyDrag = claim
            spaceGesture.noteDrag()
            return
        }
        if !onChrome, persistsPlacement, keyboard.mode != .edit, let claim = beginRegionDrag(at: start) {
            regionDrag = claim
            spaceGesture.noteDrag()
            return
        }
        let draggable = onChrome ? nil : draggableTopic(at: start)
        let target: CanvasPressTarget = onChrome ? .chrome : (draggable == nil ? .blank : .draggableNode)
        let intent = CanvasPointerRouter.intent(
            target: target,
            mode: pointerRoutingMode,
            spaceHeld: spaceHeld,
            isEditing: keyboard.mode == .edit,
            allowsPlacement: persistsPlacement
        )
        // Any drag spends a Space hold: releasing the key afterwards must never
        // fall through to 编辑主题.
        if intent != .ignore {
            spaceGesture.noteDrag()
        }
        switch intent {
        case .ignore:
            ignoreDrag = true
        case .dragNode:
            guard let draggable,
                  let frame = placedFrames().first(where: { $0.id == draggable })?.frame else {
                panAnchor = camera.viewport.offset
                return
            }
            drag = RootDrag(
                id: draggable,
                grabX: start.x - frame.minX,
                grabY: start.y - frame.minY
            )
        case .pan:
            panAnchor = camera.viewport.offset
        case .marquee:
            marquee = CanvasMarqueeState(
                start: start,
                baseSelection: keyboard.selectedNodeIDs,
                additive: shiftIsDown
            )
        }
        #if os(macOS)
        syncPointerCursor()
        #endif
    }

    /// A hierarchy root or a free topic under the press. Tree children are not
    /// draggable, so they read as blank paper and a marquee may sweep them.
    private func draggableTopic(at canvasPoint: CGPoint) -> UUID? {
        guard let id = CanvasPlacement.draggableID(at: canvasPoint, in: layoutSource()) else { return nil }
        return document.parentID(of: id) == nil ? id : nil
    }

    /// The marquee as it grows and shrinks. Shift can go down or up mid-drag, so
    /// the merge flag follows the keyboard instead of the press.
    private func updateMarquee(to point: CGPoint) {
        guard var state = marquee else { return }
        state.extend(to: point)
        state.additive = shiftIsDown
        marquee = state
        applyNodeSelection(state.selection(in: placedFrames()))
        #if os(macOS)
        syncPointerCursor()
        #endif
    }

    /// Writes a set the marquee produced.
    ///
    /// The set goes in first and the primary topic is chosen from inside it:
    /// assigning `selectedNodeID` a topic that is not in `selectedNodeIDs` would
    /// replace the set, which is exactly what a marquee must not do.
    private func applyNodeSelection(_ ids: Set<UUID>) {
        guard ids != keyboard.selectedNodeIDs else { return }
        let primary = keyboard.selectedNodeID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        keyboard.selectedNodeIDs = ids
        keyboard.selectedNodeID = primary
        interaction.selectedNodeID = primary
    }

    /// Escape: drop the rectangle and put back the selection the drag started
    /// from. `ignoreDrag` keeps the rest of the same drag from starting another.
    private func cancelMarquee() {
        guard let cancelled = marquee else { return }
        marquee = nil
        ignoreDrag = true
        applyNodeSelection(cancelled.cancelledSelection)
        #if os(macOS)
        syncPointerCursor()
        #endif
    }

    /// Space down: borrow the hand now. No threshold wait, so the cursor and the
    /// drag change on the key press instead of a quarter second later.
    private func beginSpaceHold() -> Bool {
        switch spaceGesture.keyDown(at: Date().timeIntervalSinceReferenceDate) {
        case .begin:
            spaceHeld = true
            #if os(macOS)
            syncPointerCursor()
            #endif
            return true
        case .repeatIgnored:
            // Auto-repeat of the press already held: not a new tap, and the
            // clock keeps running from the first key down.
            return true
        default:
            return false
        }
    }

    /// Space up: a quick tap that never dragged is still 编辑主题. A hold, or a
    /// press spent panning, does nothing.
    private func endSpaceHold() -> Bool {
        let wasHeld = spaceHeld
        spaceHeld = false
        #if os(macOS)
        syncPointerCursor()
        #endif
        switch spaceGesture.keyUp(at: Date().timeIntervalSinceReferenceDate) {
        case .end(.edit):
            guard wasHeld, keyboard.mode == .command, canvasFocused else { return true }
            _ = handleKey(
                KeyEvent(key: .space, modifiers: [], mode: .command, isComposing: keyboard.isComposing)
            )
            return true
        case .end(.none), .begin, .repeatIgnored:
            return true
        case .strayUp:
            return false
        }
    }

    /// The marquee's own sketch: a 1 pt accent outline over an 8% wash. It takes
    /// no hit, so the drag that draws it keeps running underneath.
    @ViewBuilder
    private var marqueeRect: some View {
        if let marquee {
            let rect = camera.viewport.viewRect(fromCanvas: marquee.rect)
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 1)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .accessibilityIdentifier("canvas.marquee")
        }
    }


    // MARK: pointer mode

    /// The mode the preference asks for. iPhone and iPad run as the hand
    /// regardless, so their drags stay exactly the ones they shipped with.
    private var pointerRoutingMode: CanvasPointerMode {
        #if os(macOS)
        return pointerMode
        #else
        return .pan
        #endif
    }

    /// The mode in force right now, Space included. The only reader of the
    /// borrowed hand is the cursor; the router takes the two parts separately.
    private var effectivePointerMode: CanvasPointerMode {
        pointerRoutingMode.effective(spaceHeld: spaceHeld)
    }

    /// Shift at this instant. `DragGesture.Value` carries no modifier flags, so
    /// the window's flags are the truth; the marquee re-reads them on every
    /// update, which is what makes Shift work when it goes down mid-drag.
    private var shiftIsDown: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.shift)
        #else
        return false
        #endif
    }

    #if os(macOS)
    /// The cursor this moment wants, or nil for the system arrow.
    private var wantedPointerCursor: CanvasCursorKind? {
        guard effectivePointerMode == .pan else { return nil }
        if panAnchor != nil { return .closedHand }
        return hoveringCanvas ? .openHand : nil
    }

    /// At most one cursor of ours sits on the stack: a change pops before it
    /// pushes, clearing pops and forgets, and leaving the canvas pops too. That
    /// is what keeps the stack from growing as the pointer crosses the canvas.
    private func syncPointerCursor() {
        let wanted = wantedPointerCursor
        guard wanted != pushedCursor else { return }
        if pushedCursor != nil {
            NSCursor.pop()
            pushedCursor = nil
        }
        guard let wanted else { return }
        wanted.nsCursor.push()
        pushedCursor = wanted
    }
    #endif

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
                // Pinch-shot UI tests hold mid-gesture scales (85/70/55),
                // which are not legal ZoomStop values. Do not snap those away.
                if !CanvasScaleHook.isEnabled {
                    camera.viewport.snapToStop(around: center(of: size))
                }
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            }
    }

    private func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func applyPendingHeldCanvasScale(in size: CGSize) {
        guard let scale = CanvasScaleHook.pendingScale() else { return }
        camera.viewport.zoom(to: scale, around: center(of: size))
        camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
        CanvasScaleHook.markApplied(scale)
    }

    @ViewBuilder
    private var heldCanvasScaleLabel: some View {
        if CanvasScaleHook.isEnabled {
            Text("pinch scale \(Int((camera.viewport.scale * 100).rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(12)
                .accessibilityIdentifier("uitest.heldCanvasScale")
                .allowsHitTesting(false)
        }
    }

    /// `-FlorettaPerfNodes` only. Uses the same camera path as pan and pinch, and the same live-origin path as a node drag.
    private func startPerfRunIfRequested() {
        guard let nodeCount = CanvasPerfRun.requestedNodeCount else { return }
        let camera = camera
        let binding = $document
        let canvas = self
        CanvasPerfDriver.start(nodeCount: nodeCount, hooks: CanvasPerfDriver.Hooks(
            viewSize: { camera.viewSize },
            offset: { camera.viewport.offset },
            setOffset: { camera.viewport.offset = $0 },
            scale: { camera.viewport.scale },
            zoom: { scale, anchor in
                camera.viewport.zoom(to: scale, around: anchor)
                camera.chrome.syncZoomPercent(toScale: camera.viewport.scale)
            },
            dragTarget: {
                // A free topic when the map has one. Dragging a root stores its point, and the layout then places that root alone.
                let document = binding.wrappedValue
                guard let id = document.freeNodes.first?.id ?? document.roots.first?.id,
                      let frame = canvas.placedFrames().first(where: { $0.id == id }) else { return nil }
                return (id, frame.frame.origin)
            },
            move: { id, origin in
                camera.liveNodeOrigin = (id, origin)
            }
        ))
    }

    private func draw(in context: GraphicsContext, size: CGSize, at time: TimeInterval) {
        // One lock to snapshot the font tables; per-node draws then read
        // immutable CTFont references. prepareCanvasFonts below resolves
        // unique (design, size) pairs for this scale before the node loop.
        ThemeFontCascade.beginFrame()
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
                    straight: branchIsStraight || CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
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
                    straight: branchIsStraight || CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link),
                    opacity: ghost.pose.opacity,
                    in: context
                )
            }
        } else {
            ghosts = []
            let straightBranch = branchIsStraight
            for node in placed where linkIDs.contains(node.id) {
                guard let link = node.link else { continue }
                let straight = straightBranch || CanvasDrawPolicy.useStraightLink(nodeCount: placed.count, link: link)
                stroke(link, straight: straight, in: context)
                drawBranchEnd(link, straight: straight, in: context)
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
        CanvasPerfRun.noteVisible(visible.count)
        ThemeFontCascade.prepareCanvasFonts(
            familyID: appearanceProfile.fontFamilyID,
            designsAndSizes: (visible + ghosts.map(\.frame)).map { node in
                (
                    node.fontDesign,
                    CanvasTextScale.onScreenPointSize(fontSize: node.fontSize, scale: scale)
                )
            }
        )
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

    /// 分支 · 线条. The document token wins over the density fallback: a map set to
    /// 直线 draws straight at every node count, and the PNG/PDF export matches it.
    private var branchIsStraight: Bool {
        BranchStyle.line(document.branchLineStyle) == .straight
    }

    /// 分支 · 终点. Drawn after the link so the marker sits on top of the tapered fill.
    private func drawBranchEnd(_ link: LinkCurve, straight: Bool, in context: GraphicsContext) {
        switch BranchStyle.endMarker(document.branchEndMarker) {
        case .none:
            return
        case .arrow:
            let tip = camera.viewport.viewPoint(fromCanvas: link.end)
            let from = camera.viewport.viewPoint(fromCanvas: straight ? link.start : link.control2)
            let head = BranchStyle.arrow(tip: tip, from: from)
            var path = Path()
            path.move(to: tip)
            path.addLine(to: head.left)
            path.addLine(to: head.right)
            path.closeSubpath()
            context.fill(path, with: .color(color(link.color)))
        case .dot:
            // Same constant width convention as the branch stroke, so it reads at any zoom.
            let radius = BranchStyle.dotRadius(lineWidth: link.endWidth)
            let center = camera.viewport.viewPoint(fromCanvas: link.end)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color(link.color)))
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
        let selected = interaction.selectedNodeID == node.id || keyboard.selectedNodeIDs.contains(node.id)
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
           let hash = node.thumbnailHashes.first ?? node.audioWaveformHashes.first,
           let image = thumbnails?.image(for: hash) {
            let imageRect = ImagePlacement.rect(for: image, in: rect)
            layer.draw(Image(decorative: image, scale: 1), in: imageRect)
            if let duration = thumbnails?.mediaDurations[hash] {
                let label = Text(MediaPreviewPolicy.durationLabel(seconds: duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                let labelRect = CGRect(x: imageRect.maxX - 48, y: imageRect.maxY - 19, width: 44, height: 16)
                let badge = Path(roundedRect: labelRect, cornerRadius: 4)
                layer.fill(badge, with: .color(.black.opacity(0.62)))
                layer.draw(label, at: CGPoint(x: labelRect.midX, y: labelRect.midY), anchor: .center)
            }
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
            let shown = NodeAttachmentDrawing.canvasText(
                title: node.text,
                caption: node.caption,
                fileBadges: node.fileBadges
            )
            let subtitleHeight = node.subtitle.isEmpty ? 0 : node.subtitleHeight * scale + 2 * scale
            var titleRect = textRect
            titleRect.size.height = max(0, textRect.height - subtitleHeight)
            var textLayer = layer
            textLayer.clip(to: Path(titleRect))
            // `draw(in:)` wraps at the node width but starts at the leading/top
            // edge, and SwiftUI's `Text` ignores the paragraph style's centering,
            // so the preview sat in the corner while the editor centered the same
            // string. Break the text with the same attributes MapExport uses and
            // paint each line at its own mid point instead.
            for line in CenteredNodeTextLayout.lines(
                shown,
                lineHeight: appearanceProfile.lineHeight,
                familyID: appearanceProfile.fontFamilyID,
                nodeDesign: node.fontDesign,
                size: pointSize,
                in: titleRect
            ) {
                textLayer.draw(
                    styledText(line.text, node: node, pointSize: pointSize),
                    at: line.center,
                    anchor: .center
                )
            }
            if !node.subtitle.isEmpty, subtitleHeight > 1 {
                let subtitleRect = CGRect(
                    x: textRect.minX,
                    y: titleRect.maxY,
                    width: textRect.width,
                    height: min(subtitleHeight, textRect.maxY - titleRect.maxY)
                )
                let subtitleSize = CanvasTextScale.onScreenPointSize(fontSize: node.subtitleFontSize, scale: scale)
                var subtitleLayer = layer
                subtitleLayer.clip(to: Path(subtitleRect))
                for line in CenteredNodeTextLayout.lines(
                    node.subtitle,
                    lineHeight: appearanceProfile.lineHeight,
                    familyID: appearanceProfile.fontFamilyID,
                    nodeDesign: node.fontDesign,
                    size: subtitleSize,
                    in: subtitleRect
                ) {
                    subtitleLayer.draw(
                        styledSubtitle(line.text, node: node, pointSize: subtitleSize),
                        at: line.center,
                        anchor: .center
                    )
                }
            }
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
        KeyLatencyProbe.shared.countThumbnailSync()
        let view = camera.viewport.canvasRect(in: camera.viewSize)
        let viewport = AttachmentViewportRect(
            minX: view.minX,
            minY: view.minY,
            maxX: view.maxX,
            maxY: view.maxY
        )
        let nodes = laidOut.frames(for: document, scheme: branchScheme, profile: appearanceProfile).map { frame in
            (
                AttachmentViewportRect(
                    minX: frame.origin.x,
                    minY: frame.origin.y,
                    maxX: frame.origin.x + frame.size.width,
                    maxY: frame.origin.y + frame.size.height
                ),
                frame.thumbnailHashes + frame.audioWaveformHashes
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

    private func styledText(_ shown: String, node: NodeFrame, pointSize: CGFloat) -> Text {
        var text = NodeTextTypography.canvasText(
            shown,
            lineHeight: appearanceProfile.lineHeight,
            familyID: appearanceProfile.fontFamilyID,
            nodeDesign: node.fontDesign,
            size: pointSize
        )
            .foregroundColor(color(node.textColor))
        if node.bold { text = text.bold() }
        if node.italic { text = text.italic() }
        if node.strikethrough { text = text.strikethrough() }
        if node.underline { text = text.underline() }
        return text
    }

    /// Subtitles keep their own ink: the theme face and the bold/italic flags
    /// belong to the title only, as before this change.
    private func styledSubtitle(_ shown: String, node: NodeFrame, pointSize: CGFloat) -> Text {
        NodeTextTypography.canvasText(
            shown,
            lineHeight: appearanceProfile.lineHeight,
            familyID: appearanceProfile.fontFamilyID,
            nodeDesign: node.fontDesign,
            size: pointSize
        )
        .foregroundColor(color(node.textColor).opacity(0.72))
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
    var identifier: String

    var body: some View {
        #if os(macOS)
        MacNodeChromeProbe(identifier: identifier)
        #else
        IOSNodeChromeProbe(identifier: identifier)
        #endif
    }
}

#if os(macOS)
private struct MacNodeChromeProbe: NSViewRepresentable {
    var identifier: String

    func makeNSView(context: Context) -> NodeChromeProbeNSView {
        let view = NodeChromeProbeNSView()
        view.probeIdentifier = identifier
        return view
    }

    func updateNSView(_ nsView: NodeChromeProbeNSView, context: Context) {
        nsView.probeIdentifier = identifier
        nsView.publish()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NodeChromeProbeNSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.bounds.width, height: proposal.height ?? nsView.bounds.height)
    }
}

private final class NodeChromeProbeNSView: NSView {
    var probeIdentifier = "" {
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
        setAccessibilityIdentifier(probeIdentifier)
        guard let window else { return }
        setAccessibilityFrame(window.convertToScreen(convert(bounds, to: nil)))
    }
}
#else
private struct IOSNodeChromeProbe: UIViewRepresentable {
    var identifier: String

    func makeUIView(context: Context) -> NodeChromeProbeUIView {
        let view = NodeChromeProbeUIView()
        view.probeIdentifier = identifier
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: NodeChromeProbeUIView, context: Context) {
        uiView.probeIdentifier = identifier
        uiView.publish()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NodeChromeProbeUIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
}

private final class NodeChromeProbeUIView: UIView {
    var probeIdentifier = "" {
        didSet { publish() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    func publish() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        isAccessibilityElement = true
        accessibilityIdentifier = probeIdentifier
        accessibilityFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
    }
}
#endif

/// How a topic looks while its text field is open.
/// The field keeps the node's fill, type, and frame. One accent stroke is added.
/// Marked text may widen the field; a line that already fits does not.
enum NodeEditChrome {
    static func probeIdentifier(editing: Bool, fill: BranchColor) -> String {
        "canvas.node.chrome.\(editing ? "edit" : "idle").fill-\(hex(fill).dropFirst())"
    }
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

    /// One burgundy topic, short enough that the old 88×36 edit field would grow it.
    static func sampleDocument(clock: any ClockPort) -> MindMapDocument {
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
        let now = clock.now()
        return MindMapDocument(title: "样式", createdAt: now, modifiedAt: now, roots: [node])
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
    var textAlignment: MindMapTextAlignment = .center
}

private extension MindMapTextAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
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
    private var cachedProfile: AppearanceProfile?
    /// Increments only when the cache misses. Petal playback must not move this.
    private(set) var layoutPassCount = 0

    func frames(for document: MindMapDocument, scheme: MapColorScheme, profile: AppearanceProfile? = nil) -> [NodeFrame] {
        if let source, source == document, cachedScheme == scheme, cachedProfile == profile { return cached }
        layoutPassCount += 1
        cached = KeyLatencyProbe.shared.timeLayout {
            CanvasPlacement.nodes(in: document, scheme: scheme, profile: profile)
        }
        source = document
        cachedScheme = scheme
        cachedProfile = profile
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
    private(set) var mediaDurations: [String: Double] = [:]
    private var durationInFlight: Set<String> = []

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
        mediaDurations = mediaDurations.filter { visible.contains($0.key) }
        for hash in visible where images[hash] == nil && !inFlight.contains(hash) && !failed.contains(hash) {
            let plan = ImageDecodePlanKind.thumbnail(hash: hash)
            guard plan.storesInThumbnailCache else { continue }
            let entry = entries.first { $0.sha256 == hash }
            guard let entry,
                  let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension,
                  AttachmentKind.isImageExtension(ext) || NodeMediaKind.classify(filename: "x.\(ext)") != .other else { continue }
            guard let cache, let archiveURL, let spillDirectory else { continue }
            inFlight.insert(hash)
            if NodeMediaKind.classify(filename: "x.\(ext)") != .other,
               mediaDurations[hash] == nil, !durationInFlight.contains(hash) {
                durationInFlight.insert(hash)
                let durationBridge = ThumbnailDurationPublish(memory: self)
                Task.detached(priority: .utility) {
                    let duration = await Self.mediaDuration(
                        entry: entry, archiveURL: archiveURL, spillDirectory: spillDirectory
                    )
                    durationBridge.finish(hash: hash, duration: duration)
                }
            }
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
        if let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension,
           NodeMediaKind.classify(filename: "x.\(ext)") == .video {
            return produceVideoThumbnail(
                entry: entry,
                hash: entry.sha256 ?? "",
                cache: cache,
                archiveURL: archiveURL,
                spillDirectory: spillDirectory
            )
        }
        if let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension,
           NodeMediaKind.classify(filename: "x.\(ext)") == .audio {
            return produceAudioWaveform(
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

    /// Reads decoded PCM in bounded batches off the main actor and persists a compact waveform.
    nonisolated private static func produceAudioWaveform(
        entry: ZipStoredEntry,
        hash: String,
        cache: ThumbnailFileCache,
        archiveURL: URL,
        spillDirectory: URL
    ) -> Data? {
        let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension ?? "m4a"
        let url = spillDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.createDirectory(at: spillDirectory, withIntermediateDirectories: true)
            try FilePreviewSpill.write(entry: entry, archiveURL: archiveURL, to: url, files: FoundationStreamingFiles())
            defer { try? FileManager.default.removeItem(at: url) }
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .audio).first else { return nil }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }
            var peaks: [Float] = []
            let bucketSamples = 4096
            var peak: Float = 0
            var inBucket = 0
            while let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
                let length = CMBlockBufferGetDataLength(buffer)
                let floats = length / MemoryLayout<Float>.size
                var data = [Float](repeating: 0, count: floats)
                let status = data.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                for value in data {
                    peak = max(peak, abs(value.isFinite ? value : 0))
                    inBucket += 1
                    if inBucket == bucketSamples {
                        peaks.append(peak)
                        peak = 0
                        inBucket = 0
                    }
                }
            }
            if inBucket > 0 { peaks.append(peak) }
            guard reader.status == .completed else { return nil }
            let bounded = MediaPreviewPolicy.boundedSamples(peaks)
            guard let image = waveformImage(bounded) else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            let result = data as Data
            try cache.store(result, for: hash)
            return result
        } catch {
            return nil
        }
    }

    nonisolated private static func waveformImage(_ peaks: [Float]) -> CGImage? {
        let width = max(1, peaks.count)
        let height = 80
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.45, alpha: 1))
        let middle = CGFloat(height) / 2
        for (index, value) in peaks.enumerated() {
            let amplitude = max(1, CGFloat(min(1, value)) * middle)
            context.fill(CGRect(x: CGFloat(index), y: middle - amplitude, width: 1, height: amplitude * 2))
        }
        return context.makeImage()
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

    fileprivate func finishDuration(hash: String, duration: Double?) {
        durationInFlight.remove(hash)
        if let duration, duration.isFinite, duration >= 0 { mediaDurations[hash] = duration }
    }

    nonisolated private static func mediaDuration(
        entry: ZipStoredEntry, archiveURL: URL, spillDirectory: URL
    ) async -> Double? {
        guard let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension else { return nil }
        let url = spillDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.createDirectory(at: spillDirectory, withIntermediateDirectories: true)
            try FilePreviewSpill.write(entry: entry, archiveURL: archiveURL, to: url, files: FoundationStreamingFiles())
            defer { try? FileManager.default.removeItem(at: url) }
            let time = try await AVURLAsset(url: url).load(.duration)
            let seconds = CMTimeGetSeconds(time)
            return seconds.isFinite ? seconds : nil
        } catch { return nil }
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

private final class ThumbnailDurationPublish: @unchecked Sendable {
    nonisolated(unsafe) private let memory: AttachmentThumbnailMemory
    init(memory: AttachmentThumbnailMemory) { self.memory = memory }
    func finish(hash: String, duration: Double?) {
        let memory = memory
        Task { @MainActor in memory.finishDuration(hash: hash, duration: duration) }
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
    /// Origin of the topic being dragged, applied on top of the last layout.
    /// The document is not rewritten until the drag ends, so the editor body and toolbar stay still.
    var liveNodeOrigin: (id: UUID, origin: CGPoint)? = nil

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

    func centerOn(_ canvasRect: CGRect) {
        guard viewSize.width > 1, viewSize.height > 1 else { return }
        let target = CGPoint(x: canvasRect.midX, y: canvasRect.midY)
        let current = viewport.viewPoint(fromCanvas: target)
        var updated = viewport
        updated.pan(by: CGSize(width: center.x - current.x, height: center.y - current.y))
        viewport = updated
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

/// Polls the UI-test scale file only when `-FlorettaPinchShot` is set.
private struct HeldCanvasScaleTick: View {
    var onTick: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear(perform: onTick)
            .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
                onTick()
            }
    }
}

#if os(macOS)
/// The cursors the two pointer modes use on the Mac canvas. Only these two ever
/// go on the stack, and `syncPointerCursor` keeps at most one of them there.
private enum CanvasCursorKind: Equatable {
    case openHand
    case closedHand

    var nsCursor: NSCursor {
        switch self {
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        }
    }
}
#endif
