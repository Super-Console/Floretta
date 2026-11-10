import Foundation

extension MindMapDocument {
    /// Sheets in this file. The first is `roots`; the rest are `additionalCanvases`.
    public var canvasCount: Int { 1 + additionalCanvases.count }

    /// Index the editor should treat as current. Out of range reads as the first sheet.
    public var clampedCanvasIndex: Int {
        guard activeCanvasIndex >= 0, activeCanvasIndex < canvasCount else { return 0 }
        return activeCanvasIndex
    }

    public func canvasTitle(at index: Int) -> String {
        guard index >= 0, index < canvasCount else { return "" }
        if index == 0 {
            if let primaryCanvasTitle, !primaryCanvasTitle.isEmpty { return primaryCanvasTitle }
            return title
        }
        return additionalCanvases[index - 1].title
    }

    public func viewport(forCanvas index: Int) -> CanvasViewportState {
        guard index >= 0, index < canvasCount else { return .standard }
        if index == 0 { return primaryCanvasViewport }
        return additionalCanvases[index - 1].viewport
    }

    /// Stores zoom and pan on one sheet. An unchanged camera does not rewrite the value.
    public mutating func setViewport(_ viewport: CanvasViewportState, forCanvas index: Int) {
        guard index >= 0, index < canvasCount else { return }
        let viewport = CanvasViewportState.clamped(viewport)
        if self.viewport(forCanvas: index) == viewport { return }
        if index == 0 {
            primaryCanvasViewport = viewport
        } else {
            additionalCanvases[index - 1].viewport = viewport
        }
    }

    public mutating func selectCanvas(_ index: Int) {
        guard index >= 0, index < canvasCount else { return }
        activeCanvasIndex = index
    }

    /// Appends a sheet with one center topic and selects it.
    @discardableResult
    public mutating func addCanvas() -> Int {
        let name = nextCanvasTitle()
        additionalCanvases.append(MindMapCanvas(
            title: name,
            roots: [MindMapNode(text: "中心")]
        ))
        activeCanvasIndex = additionalCanvases.count
        return activeCanvasIndex
    }

    public mutating func renameCanvas(at index: Int, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, index >= 0, index < canvasCount else { return }
        if index == 0 {
            primaryCanvasTitle = trimmed
        } else {
            additionalCanvases[index - 1].title = trimmed
        }
    }

    /// The one canvas a frame should lay out or edit.
    /// Other sheets are not copied into this value, so measuring it cannot walk them.
    public func isolatedCanvas(at index: Int) -> MindMapDocument {
        let index = storedIndex(index)
        if index == 0 {
            return MindMapDocument(
                title: title,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                roots: roots,
                freeNodes: freeNodes,
                relationships: relationships,
                stickies: stickies,
                formatVersion: formatVersion,
                themeID: themeID
            )
        }
        let canvas = additionalCanvases[index - 1]
        return MindMapDocument(
            title: canvas.title,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            roots: canvas.roots,
            freeNodes: canvas.freeNodes,
            relationships: canvas.relationships,
            stickies: canvas.stickies,
            formatVersion: formatVersion,
            themeID: themeID
        )
    }

    /// Writes one sheet's topics, relationships, stickies, and the shared theme back.
    /// Other sheets, the active index, and every camera stay where they are.
    public mutating func replaceCanvasContent(at index: Int, with surface: MindMapDocument) {
        let index = storedIndex(index)
        themeID = MapThemeCatalog.persistedID(surface.themeID)
        if index == 0 {
            roots = surface.roots
            freeNodes = surface.freeNodes
            relationships = surface.relationships
            stickies = surface.stickies
            return
        }
        additionalCanvases[index - 1].roots = surface.roots
        additionalCanvases[index - 1].freeNodes = surface.freeNodes
        additionalCanvases[index - 1].relationships = surface.relationships
        additionalCanvases[index - 1].stickies = surface.stickies
    }

    /// Formats that hold one tree: Markdown, OPML, FreeMind, TextBundle, PNG, and PDF.
    /// Index 0 returns this document so an imported foreign bag still round-trips.
    /// A later sheet returns only that sheet. The receiver is not modified.
    /// `.floretta` and `.xmind` do not use this; they keep every canvas.
    public func singleTreeExport() -> MindMapDocument {
        let index = clampedCanvasIndex
        if index == 0 { return self }
        return isolatedCanvas(at: index)
    }

    /// Topics on every sheet. Attachment accounting uses this so a later sheet's
    /// files are not treated as orphans. Search and tag filters stay on `walkTopics`.
    public func walkAllCanvasTopics(_ visit: (MindMapNode) -> Void) {
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                visit(node)
                walk(node.children)
            }
        }
        walk(roots)
        walk(freeNodes)
        for canvas in additionalCanvases {
            walk(canvas.roots)
            walk(canvas.freeNodes)
        }
    }

    mutating func clampActiveCanvasIndex() {
        activeCanvasIndex = clampedCanvasIndex
    }

    private func storedIndex(_ index: Int) -> Int {
        guard index >= 0, index < canvasCount else { return 0 }
        return index
    }

    private func nextCanvasTitle() -> String {
        var existing: Set<String> = [canvasTitle(at: 0)]
        for canvas in additionalCanvases {
            existing.insert(canvas.title)
        }
        if !existing.contains("新画布") { return "新画布" }
        var number = 2
        while existing.contains("新画布 \(number)") {
            number += 1
        }
        return "新画布 \(number)"
    }
}
