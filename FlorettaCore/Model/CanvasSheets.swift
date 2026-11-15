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

    /// Removes one canvas while keeping at least one canvas in the document.
    /// The active index follows the nearest surviving canvas.
    @discardableResult
    public mutating func removeCanvas(at index: Int) -> Bool {
        guard canvasCount > 1, index >= 0, index < canvasCount else { return false }
        let active = clampedCanvasIndex
        if index == 0 {
            let next = additionalCanvases.removeFirst()
            roots = next.roots
            freeNodes = next.freeNodes
            relationships = next.relationships
            stickies = next.stickies
            regions = next.regions
            primaryCanvasTitle = next.title == title ? nil : next.title
            primaryCanvasViewport = next.viewport
        } else {
            additionalCanvases.remove(at: index - 1)
        }
        if active == index {
            activeCanvasIndex = min(index, canvasCount - 1)
        } else if active > index {
            activeCanvasIndex = active - 1
        } else {
            activeCanvasIndex = active
        }
        return true
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
                regions: regions,
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
            regions: canvas.regions,
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
            regions = surface.regions
            return
        }
        additionalCanvases[index - 1].roots = surface.roots
        additionalCanvases[index - 1].freeNodes = surface.freeNodes
        additionalCanvases[index - 1].relationships = surface.relationships
        additionalCanvases[index - 1].stickies = surface.stickies
        additionalCanvases[index - 1].regions = surface.regions
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

    /// The one sheet at `index`, camera included, as a value that can be filed away
    /// and put back. Nil when the index is out of range.
    ///
    /// `MindMapCanvas.id` is not a document-level identity: slot 0 keeps its sheet in
    /// the document's own fields, so the id here is fresh on every call. Compare
    /// sheets by title and content, not by that id.
    public func canvasSnapshot(at index: Int) -> MindMapCanvas? {
        guard index >= 0, index < canvasCount else { return nil }
        if index == 0 {
            return MindMapCanvas(
                title: canvasTitle(at: 0),
                roots: roots,
                freeNodes: freeNodes,
                relationships: relationships,
                stickies: stickies,
                regions: regions,
                viewport: primaryCanvasViewport
            )
        }
        return additionalCanvases[index - 1]
    }

    /// Puts a sheet back at `index` and selects it. The inverse of `removeCanvas`.
    ///
    /// Slot 0 keeps its sheet in the document's own fields, so inserting there pushes
    /// the current head down into `additionalCanvases[0]` instead of dropping it.
    public mutating func insertCanvas(_ canvas: MindMapCanvas, at index: Int) {
        let index = min(max(index, 0), canvasCount)
        if index == 0 {
            let head = MindMapCanvas(
                title: canvasTitle(at: 0),
                roots: roots,
                freeNodes: freeNodes,
                relationships: relationships,
                stickies: stickies,
                regions: regions,
                viewport: primaryCanvasViewport
            )
            additionalCanvases.insert(head, at: 0)
            roots = canvas.roots
            freeNodes = canvas.freeNodes
            relationships = canvas.relationships
            stickies = canvas.stickies
            regions = canvas.regions
            primaryCanvasTitle = canvas.title == title ? nil : canvas.title
            primaryCanvasViewport = CanvasViewportState.clamped(canvas.viewport)
        } else {
            additionalCanvases.insert(canvas, at: index - 1)
        }
        activeCanvasIndex = index
    }

    /// Copies one sheet right after itself and selects the copy.
    /// Every node, sticky, region, and relationship gets a fresh id: two sheets must
    /// never share one, because selection, links, and undo all address ids.
    /// An empty `title` falls back to 「<原画布> 副本」.
    @discardableResult
    public mutating func duplicateCanvas(at index: Int, title: String? = nil) -> Int? {
        guard let source = canvasSnapshot(at: index) else { return nil }
        var copy = source.copyWithFreshIDs()
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copy.title = trimmed.isEmpty
            ? uniqueCanvasTitle(basedOn: source.title, suffix: "副本")
            : trimmed
        insertCanvas(copy, at: index + 1)
        return index + 1
    }

    /// 「<base> 副本」, then 「<base> 副本 2」… — never a title another sheet already has.
    /// The suffix arrives from the caller so the shell can localize it.
    public func uniqueCanvasTitle(basedOn base: String, suffix: String) -> String {
        var existing: Set<String> = []
        for index in 0..<canvasCount {
            existing.insert(canvasTitle(at: index))
        }
        let stem = "\(base) \(suffix)"
        if !existing.contains(stem) { return stem }
        var number = 2
        while existing.contains("\(stem) \(number)") {
            number += 1
        }
        return "\(stem) \(number)"
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

extension MindMapCanvas {
    /// A copy with a fresh id on every topic, summary, boundary, relationship,
    /// sticky, region, and on the sheet itself.
    ///
    /// Ids must not repeat: the canvas selects, links, and undoes by id, so a copy
    /// that shared them would fight the original. Everything else is kept: text,
    /// notes, styles, free positions, labels, markers, summary and boundary ranges
    /// (they are child indexes, not ids), and attachment hashes.
    /// A relationship whose endpoint is not on this sheet is dropped: it has nowhere
    /// to point once the ids are new.
    public func copyWithFreshIDs() -> MindMapCanvas {
        var idMap: [UUID: UUID] = [:]

        func fresh(_ nodes: [MindMapNode]) -> [MindMapNode] {
            nodes.map { node in
                let newID = UUID()
                idMap[node.id] = newID
                var copy = node
                copy.id = newID
                copy.children = fresh(node.children)
                copy.summaries = node.summaries.map { summary in
                    var mark = summary
                    mark.id = UUID()
                    return mark
                }
                copy.boundaries = node.boundaries.map { boundary in
                    var mark = boundary
                    mark.id = UUID()
                    return mark
                }
                return copy
            }
        }

        var copy = self
        copy.id = UUID()
        copy.roots = fresh(roots)
        copy.freeNodes = fresh(freeNodes)
        copy.relationships = relationships.compactMap { relationship in
            guard let sourceID = idMap[relationship.sourceID],
                  let targetID = idMap[relationship.targetID] else { return nil }
            return TopicRelationship(
                id: UUID(),
                sourceID: sourceID,
                targetID: targetID,
                title: relationship.title
            )
        }
        copy.stickies = stickies.map { sticky in
            var card = sticky
            card.id = UUID()
            return card
        }
        copy.regions = regions.map { region in
            var zone = region
            zone.id = UUID()
            return zone
        }
        return copy
    }
}
