import XCTest
@testable import FlorettaCore

/// Canvas sheet capsule: the model half. Snapshot / insert / duplicate / removal
/// history are what the bottom-left capsule's `▾` menu calls into.
final class CanvasSheetMenuTests: XCTestCase {
    // MARK: - Snapshot

    func testSnapshotReadsEachSlotWithItsOwnTitleAndCamera() throws {
        var document = MindMapDocument(title: "甲", roots: [MindMapNode(text: "第一")])
        document.addCanvas()
        document.renameCanvas(at: 1, to: "乙页")
        document.setViewport(CanvasViewportState(scale: 1.5, offsetX: 20, offsetY: -4), forCanvas: 0)
        document.setViewport(CanvasViewportState(scale: 2.5, offsetX: -7, offsetY: 8), forCanvas: 1)

        let first = try XCTUnwrap(document.canvasSnapshot(at: 0))
        XCTAssertEqual(first.title, "甲")
        XCTAssertEqual(first.roots.map(\.text), ["第一"])
        XCTAssertEqual(first.viewport.scale, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(first.viewport.offsetY, -4, accuracy: 0.000_001)

        let second = try XCTUnwrap(document.canvasSnapshot(at: 1))
        XCTAssertEqual(second.title, "乙页")
        XCTAssertEqual(second.roots.map(\.text), ["中心"])
        XCTAssertEqual(second.viewport.offsetX, -7, accuracy: 0.000_001)

        // A renamed first sheet reports the sheet title, not the document title.
        document.renameCanvas(at: 0, to: "甲页")
        XCTAssertEqual(document.canvasSnapshot(at: 0)?.title, "甲页")

        XCTAssertNil(document.canvasSnapshot(at: -1))
        XCTAssertNil(document.canvasSnapshot(at: 2))
    }

    // MARK: - Insert (the undo half of remove)

    func testInsertingAHeadSheetPushesTheCurrentFirstSheetDown() throws {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.addCanvas()
        document.renameCanvas(at: 1, to: "乙")
        document.setViewport(CanvasViewportState(scale: 3, offsetX: 1, offsetY: 2), forCanvas: 0)
        let before = document

        let removed = try XCTUnwrap(document.canvasSnapshot(at: 0))
        XCTAssertTrue(document.removeCanvas(at: 0))
        XCTAssertEqual(document.canvasTitle(at: 0), "乙")
        XCTAssertEqual(document.roots.map(\.text), ["中心"])

        document.insertCanvas(removed, at: 0)
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.clampedCanvasIndex, 0)
        XCTAssertEqual(document.canvasTitle(at: 0), "工程")
        XCTAssertEqual(document.roots.map(\.text), before.roots.map(\.text))
        XCTAssertEqual(document.canvasTitle(at: 1), "乙")
        XCTAssertEqual(
            document.additionalCanvases[0].roots.map(\.text),
            before.additionalCanvases[0].roots.map(\.text)
        )
        XCTAssertEqual(document.viewport(forCanvas: 0).scale, 3, accuracy: 0.000_001)
        XCTAssertEqual(document.viewport(forCanvas: 1).scale, 1, accuracy: 0.000_001)
    }

    func testInsertingAMiddleSheetRestoresItsContentAndSelection() throws {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.addCanvas()
        var middle = document.isolatedCanvas(at: 1)
        middle.roots = [MindMapNode(text: "乙根", children: [MindMapNode(text: "乙子")])]
        middle.stickies = [StickyNote(text: "乙便签", origin: MindMapPoint(x: 4, y: 5))]
        middle.regions = [CanvasRegion(label: "乙专区", origin: MindMapPoint(x: 1, y: 2))]
        document.replaceCanvasContent(at: 1, with: middle)
        document.addCanvas()
        document.renameCanvas(at: 2, to: "丙")
        document.setViewport(CanvasViewportState(scale: 2, offsetX: 9, offsetY: 0), forCanvas: 1)

        let removed = try XCTUnwrap(document.canvasSnapshot(at: 1))
        XCTAssertTrue(document.removeCanvas(at: 1))
        XCTAssertEqual(document.canvasTitle(at: 1), "丙")

        document.insertCanvas(removed, at: 1)
        XCTAssertEqual(document.canvasCount, 3)
        XCTAssertEqual(document.clampedCanvasIndex, 1)
        let restored = document.isolatedCanvas(at: 1)
        XCTAssertEqual(restored.roots.map(\.text), ["乙根"])
        XCTAssertEqual(restored.roots[0].children.map(\.text), ["乙子"])
        XCTAssertEqual(restored.stickies.map(\.text), ["乙便签"])
        XCTAssertEqual(restored.regions.map(\.label), ["乙专区"])
        XCTAssertEqual(document.viewport(forCanvas: 1).scale, 2, accuracy: 0.000_001)
        XCTAssertEqual(document.viewport(forCanvas: 1).offsetX, 9, accuracy: 0.000_001)
        XCTAssertEqual(document.canvasTitle(at: 2), "丙")
    }

    func testInsertingPastTheEndAppendsASheet() {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.insertCanvas(MindMapCanvas(title: "尾巴", roots: [MindMapNode(text: "尾")]), at: 99)
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.canvasTitle(at: 1), "尾巴")
        XCTAssertEqual(document.clampedCanvasIndex, 1)
    }

    // MARK: - Duplicate (复制 / 粘贴 share this)

    func testDuplicateCopiesTheTreeWithFreshIDs() throws {
        var root = MindMapNode(text: "根")
        root.summaries = [TopicSummary(text: "概要", rangeStart: 0, rangeEnd: 0)]
        root.boundaries = [TopicBoundary(title: "边界", rangeStart: 0, rangeEnd: 0)]
        root.children = [MindMapNode(text: "子"), MindMapNode(text: "另一个子")]
        var document = MindMapDocument(title: "工程", roots: [root])
        var surface = document.isolatedCanvas(at: 0)
        surface.relationships = [
            TopicRelationship(sourceID: root.id, targetID: root.children[0].id, title: "连接"),
        ]
        surface.stickies = [StickyNote(text: "便签", origin: MindMapPoint(x: 3, y: 4))]
        surface.regions = [CanvasRegion(label: "专区", origin: MindMapPoint(x: 0, y: 0))]
        document.replaceCanvasContent(at: 0, with: surface)

        let index = try XCTUnwrap(document.duplicateCanvas(at: 0))
        XCTAssertEqual(index, 1)
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.clampedCanvasIndex, 1)

        let original = document.isolatedCanvas(at: 0)
        let copy = document.isolatedCanvas(at: 1)
        XCTAssertEqual(copy.roots.map(\.text), ["根"])
        XCTAssertEqual(copy.roots[0].children.map(\.text), ["子", "另一个子"])
        XCTAssertEqual(copy.roots[0].summaries.map(\.text), ["概要"])
        XCTAssertEqual(copy.roots[0].boundaries.map(\.title), ["边界"])
        XCTAssertEqual(copy.roots[0].summaries[0].range, TopicChildRange(start: 0, end: 0))
        XCTAssertEqual(copy.stickies.map(\.text), ["便签"])
        XCTAssertEqual(copy.regions.map(\.label), ["专区"])

        // Every id is new: selection, links, and undo all address ids.
        let originalIDs = Set(nodeIDs(in: original))
        let copyIDs = Set(nodeIDs(in: copy))
        XCTAssertFalse(originalIDs.isEmpty)
        XCTAssertTrue(originalIDs.isDisjoint(with: copyIDs))
        XCTAssertNotEqual(copy.stickies[0].id, original.stickies[0].id)
        XCTAssertNotEqual(copy.regions[0].id, original.regions[0].id)
        XCTAssertNotEqual(copy.roots[0].summaries[0].id, original.roots[0].summaries[0].id)
        XCTAssertNotEqual(copy.roots[0].boundaries[0].id, original.roots[0].boundaries[0].id)

        // A relationship inside the sheet is kept and re-pointed at the copy's nodes.
        XCTAssertEqual(copy.relationships.count, 1)
        XCTAssertTrue(copyIDs.contains(copy.relationships[0].sourceID))
        XCTAssertTrue(copyIDs.contains(copy.relationships[0].targetID))
        XCTAssertNotEqual(copy.relationships[0].id, original.relationships[0].id)
        XCTAssertEqual(copy.relationships[0].title, "连接")
    }

    func testDuplicateDropsRelationshipsThatPointOffTheSheet() throws {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.addCanvas()
        let outside = try XCTUnwrap(document.isolatedCanvas(at: 1).roots.first?.id)
        var surface = document.isolatedCanvas(at: 0)
        surface.relationships = [
            TopicRelationship(sourceID: surface.roots[0].id, targetID: outside, title: "跨画布"),
        ]
        document.replaceCanvasContent(at: 0, with: surface)

        let index = try XCTUnwrap(document.duplicateCanvas(at: 0))
        XCTAssertTrue(document.isolatedCanvas(at: index).relationships.isEmpty)
        // The original keeps its line.
        XCTAssertEqual(document.isolatedCanvas(at: 0).relationships.count, 1)
    }

    func testDuplicateKeepsAttachmentReferences() throws {
        let hash = String(repeating: "a", count: 64)
        let node = MindMapNode(
            text: "带附件",
            attachments: [NodeAttachment(sha256: hash, fileExtension: "png", byteCount: 4, filename: "a.png")]
        )
        var document = MindMapDocument(title: "工程", roots: [node])
        let index = try XCTUnwrap(document.duplicateCanvas(at: 0))
        let copy = document.isolatedCanvas(at: index)
        XCTAssertEqual(copy.roots[0].attachments.map(\.sha256), [hash])
        XCTAssertEqual(AttachmentReferences.hashes(in: copy), [hash])
    }

    func testDuplicateTitlesAreNumbered() throws {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.renameCanvas(at: 0, to: "画布")
        XCTAssertEqual(document.uniqueCanvasTitle(basedOn: "画布", suffix: "副本"), "画布 副本")

        let first = try XCTUnwrap(document.duplicateCanvas(at: 0, title: nil))
        XCTAssertEqual(document.canvasTitle(at: first), "画布 副本")
        let second = try XCTUnwrap(document.duplicateCanvas(at: 0, title: nil))
        XCTAssertEqual(document.canvasTitle(at: second), "画布 副本 2")
        let third = try XCTUnwrap(document.duplicateCanvas(at: 0, title: "自定义"))
        XCTAssertEqual(document.canvasTitle(at: third), "自定义")
    }

    // MARK: - Removal history (删除可撤销)

    func testRemovalIsTheNewestUndoStepUntilAContentEdit() {
        var history = CanvasSheetHistory(limit: 4)
        XCTAssertFalse(history.canRestore)
        XCTAssertNil(history.undoableRemoval)

        history.recordRemoval(index: 1, canvas: MindMapCanvas(title: "乙", roots: [MindMapNode(text: "乙")]))
        XCTAssertTrue(history.canRestore)
        XCTAssertEqual(history.undoableRemoval?.index, 1)
        XCTAssertNil(history.redoableRemoval)

        // A content edit made after the delete is the newer step, so ⌘Z means the edit.
        history.noteContentEdit()
        XCTAssertNil(history.undoableRemoval)
        // The sheet can still come back from the menu.
        XCTAssertEqual(history.restorableRemoval?.index, 1)
        XCTAssertEqual(history.popRestorable()?.index, 1)
        XCTAssertFalse(history.canRestore)
    }

    func testUndoAndRedoMoveTheRemovalBetweenStacks() throws {
        var history = CanvasSheetHistory()
        history.recordRemoval(index: 2, canvas: MindMapCanvas(title: "丙", roots: [MindMapNode(text: "丙")]))

        let undone = try XCTUnwrap(history.popUndo())
        XCTAssertEqual(undone.index, 2)
        XCTAssertFalse(history.canRestore)
        XCTAssertEqual(history.redoableRemoval?.index, 2)

        let redone = try XCTUnwrap(history.popRedo())
        XCTAssertEqual(redone.index, 2)
        XCTAssertEqual(history.undoableRemoval?.index, 2)
    }

    func testANewRemovalClearsRedoAndTheLimitDropsTheOldest() {
        var history = CanvasSheetHistory(limit: 2)
        for index in 0..<2 {
            history.recordRemoval(index: index, canvas: MindMapCanvas(title: "页\(index)"))
        }
        XCTAssertEqual(history.undoable.count, 2)
        XCTAssertNotNil(history.popUndo())
        XCTAssertNotNil(history.redoableRemoval)

        history.recordRemoval(index: 5, canvas: MindMapCanvas(title: "五"))
        XCTAssertNil(history.redoableRemoval)
        XCTAssertEqual(history.undoable.count, 2)
        XCTAssertEqual(history.undoable.last?.index, 5)

        history.recordRemoval(index: 6, canvas: MindMapCanvas(title: "六"))
        XCTAssertEqual(history.undoable.map(\.index), [5, 6])

        history.clear()
        XCTAssertFalse(history.canRestore)
        XCTAssertNil(history.redoableRemoval)
    }

    /// The whole flow without a session: delete the sheet on screen, then put it back.
    /// Same three calls `EditorSession.removeCanvas` / `undoCanvasRemoval` make.
    func testDeletingTheVisibleSheetCanBeUndoneWithItsCamera() throws {
        var document = MindMapDocument(title: "工程", roots: [MindMapNode(text: "甲")])
        document.addCanvas()
        var second = document.isolatedCanvas(at: 1)
        second.roots = [MindMapNode(text: "乙")]
        document.replaceCanvasContent(at: 1, with: second)
        document.renameCanvas(at: 1, to: "乙页")

        let live = CanvasViewportState(scale: 2.25, offsetX: 33, offsetY: -12)
        var history = CanvasSheetHistory()
        var removed = try XCTUnwrap(document.canvasSnapshot(at: 1))
        // `EditorSession.removeCanvas` stamps the live camera onto the sheet it is
        // about to drop, so undo brings that camera back.
        removed.viewport = live
        document.setViewport(live, forCanvas: 1)
        XCTAssertTrue(document.removeCanvas(at: 1))
        history.recordRemoval(index: 1, canvas: removed)
        XCTAssertEqual(document.canvasCount, 1)
        XCTAssertEqual(document.clampedCanvasIndex, 0)
        // The last sheet never goes away.
        XCTAssertFalse(document.removeCanvas(at: 0))

        let undo = try XCTUnwrap(history.popUndo())
        document.insertCanvas(undo.canvas, at: undo.index)
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.clampedCanvasIndex, 1)
        XCTAssertEqual(document.canvasTitle(at: 1), "乙页")
        XCTAssertEqual(document.roots.map(\.text), ["甲"])
        XCTAssertEqual(document.isolatedCanvas(at: 1).roots.map(\.text), ["乙"])
        XCTAssertEqual(document.viewport(forCanvas: 1).scale, 2.25, accuracy: 0.000_001)
        XCTAssertEqual(document.viewport(forCanvas: 1).offsetX, 33, accuracy: 0.000_001)
    }

    private func nodeIDs(in document: MindMapDocument) -> [UUID] {
        var ids: [UUID] = []
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                ids.append(node.id)
                walk(node.children)
            }
        }
        walk(document.roots)
        walk(document.freeNodes)
        return ids
    }
}
