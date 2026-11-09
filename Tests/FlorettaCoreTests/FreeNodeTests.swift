import FlorettaCore
import XCTest

final class FreeNodeTests: XCTestCase {
    private let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let freeID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let otherID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    private let childID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
    private let linkID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testFreeNodeIsOutsideTheTreeAndKeepsItsPoint() throws {
        var document = tree()
        let before = LayoutEngine().layout(document)
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 1234, y: -567), id: freeID)
        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertFalse(document.roots.contains { $0.id == freeID })
        XCTAssertNil(document.parentID(of: freeID))
        XCTAssertFalse(document.insertChild(MindMapNode(text: "子"), under: freeID))
        XCTAssertFalse(document.canReparent(freeID, to: rootID))
        XCTAssertEqual(document.topicCount, 2)

        let frames = LayoutEngine().layout(document)
        let free = try XCTUnwrap(frames.first { $0.id == freeID })
        XCTAssertEqual(free.origin.x, 1234, accuracy: 0.001)
        XCTAssertEqual(free.origin.y, -567, accuracy: 0.001)
        XCTAssertNil(free.parentID)
        XCTAssertNil(free.link)
        XCTAssertTrue(free.isFree)
        XCTAssertFalse(free.isRoot)
        for original in before {
            let again = try XCTUnwrap(frames.first { $0.id == original.id })
            XCTAssertEqual(again.origin.x, original.origin.x, accuracy: 0.001)
            XCTAssertEqual(again.origin.y, original.origin.y, accuracy: 0.001)
            XCTAssertEqual(again.parentID, original.parentID)
        }

        var point = MindMapPoint(x: 1234, y: -567)
        for _ in 0..<5 {
            point.x += 37
            point.y -= 11
            XCTAssertTrue(document.moveFreeNode(freeID, to: point))
            let dragged = try XCTUnwrap(LayoutEngine().layout(document).first { $0.id == freeID })
            XCTAssertEqual(dragged.origin.x, point.x, accuracy: 0.001)
            XCTAssertEqual(dragged.origin.y, point.y, accuracy: 0.001)
            XCTAssertNil(dragged.link)
            XCTAssertNil(dragged.parentID)
        }
        XCTAssertFalse(document.moveFreeNode(rootID, to: MindMapPoint(x: 1, y: 1)))
        XCTAssertNil(document.roots[0].position)
    }

    func testFreeNodeChildIsCountedAndSearchedButNotLaidOut() throws {
        var document = tree()
        var free = MindMapNode(
            id: freeID,
            text: "自由",
            position: MindMapPoint(x: 40, y: 50),
            children: [MindMapNode(id: childID, text: "不进层级")]
        )
        document.freeNodes = [free]
        XCTAssertEqual(document.topicCount, 3)
        XCTAssertEqual(document.topics(matching: "不进"), [childID])
        XCTAssertTrue(document.isInFreeNodeTree(childID))
        XCTAssertFalse(document.isFreeNode(childID))
        XCTAssertNil(LayoutEngine().layout(document).first { $0.id == childID })
        XCTAssertFalse(document.insertChild(MindMapNode(text: "再"), under: freeID))
        free.position = MindMapPoint(x: 40, y: 50)
        let frame = try XCTUnwrap(LayoutEngine().layout(document).first { $0.id == freeID })
        XCTAssertEqual(frame.origin.x, 40, accuracy: 0.001)
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document), [rootID, freeID])
        XCTAssertNil(OutlineNavigator.destination(from: freeID, move: .right, in: document))
    }

    func testRelationshipIsStoredNotDrawnAndSurvivesUndo() throws {
        var document = tree()
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 8, y: 9), id: freeID)
        document.addFreeNode(text: "另一", at: MindMapPoint(x: 30, y: 12), id: otherID)
        let treeLink = try XCTUnwrap(document.linkTopics(from: rootID, to: freeID, title: "看这里", id: linkID))
        XCTAssertEqual(treeLink.sourceID, rootID)
        XCTAssertEqual(treeLink.targetID, freeID)
        let betweenFree = try XCTUnwrap(document.linkTopics(from: freeID, to: otherID))
        XCTAssertNil(document.linkTopics(from: freeID, to: freeID))
        let frames = LayoutEngine().layout(document)
        XCTAssertNil(frames.first { $0.id == freeID }?.link)
        XCTAssertNil(frames.first { $0.id == rootID }?.link)
        XCTAssertFalse(frames.contains { $0.link != nil })

        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.relationships.map(\.id), [linkID, betweenFree.id])
        XCTAssertEqual(decoded.relationships[0].title, "看这里")
        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        try assertKeyOrder(json, ["createdAt", "formatVersion", "freeNodes", "modifiedAt", "relationships", "roots", "title"])

        var session = MindMapKeyboardSession()
        session.selectedNodeID = freeID
        XCTAssertTrue(session.linkFreeNode(to: rootID, document: &document, title: "回"))
        XCTAssertEqual(document.relationships.count, 3)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.relationships.count, 2)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.relationships.count, 3)
        session.apply(.deleteSelection, document: &document, frames: [])
        XCTAssertFalse(document.freeNodes.contains { $0.id == freeID })
        XCTAssertFalse(document.relationships.contains { $0.sourceID == freeID || $0.targetID == freeID })
        session.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.freeNodes.contains { $0.id == freeID })
        XCTAssertTrue(document.relationships.contains { $0.targetID == rootID && $0.title == "回" })
    }

    func testTabOnAFreeNodeDoesNotCreateAChildOrAnUndoStep() {
        var document = tree()
        var session = MindMapKeyboardSession()
        let id = session.addFreeNode(at: MindMapPoint(x: 1, y: 2), document: &document)
        XCTAssertNotNil(id)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.freeNodes.isEmpty)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.freeNodes.count, 1)
        let free = document.freeNodes[0].id
        session.selectedNodeID = free
        let command = session.handle(
            KeyEvent(key: .tab, modifiers: [], mode: .command, isComposing: false),
            document: &document,
            frames: []
        )
        XCTAssertEqual(command, .createChild)
        XCTAssertTrue(document.freeNodes[0].children.isEmpty)
        XCTAssertEqual(document.roots[0].children.count, 0)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.freeNodes.isEmpty)
        XCTAssertTrue(document.roots[0].children.isEmpty)
    }

    func testFreeNodeCoexistsWithAttachmentAndNote() throws {
        let treeHash = String(repeating: "a", count: 64)
        let freeHash = String(repeating: "b", count: 64)
        var document = MindMapDocument(
            title: "共存",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    attachments: [
                        NodeAttachment(sha256: treeHash, fileExtension: "psd", byteCount: 10, filename: "a.psd"),
                    ]
                ),
            ]
        )
        document.addFreeNode(
            text: "自由",
            at: MindMapPoint(x: 4, y: 5),
            id: freeID,
            note: "这是节点备注，不是便签",
            attachments: [
                NodeAttachment(sha256: freeHash, fileExtension: "png", byteCount: 12, filename: "b.png"),
            ]
        )
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertEqual(document.node(freeID)?.note, "这是节点备注，不是便签")
        XCTAssertEqual(document.roots[0].attachments.map(\.filename), ["a.psd"])
        XCTAssertEqual(document.freeNodes[0].attachments.map(\.filename), ["b.png"])
        XCTAssertTrue(ImageAttachments.contains(document))
        let counts = AttachmentReferences.counts(in: document)
        XCTAssertEqual(counts.map(\.sha256), [treeHash, freeHash])
        let stored = ZipStoredEntry(
            name: "assets/\(freeHash).png",
            method: 0,
            crc32: 0,
            byteCount: 12,
            localHeaderOffset: 0,
            dataOffset: 0
        )
        XCTAssertTrue(AttachmentReferences.orphans(stored: [stored], document: document).isEmpty)
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded, document)

        let markdown = FlorettaMarkdown.export(document)
        XCTAssertFalse(markdown.contains("自由"))
        let mm = try XCTUnwrap(String(data: try FlorettaMMCodec.export(document), encoding: .utf8))
        XCTAssertFalse(mm.contains("自由"))
    }

    func testVersionOneFileWithoutTheNewKeysStillOpens() throws {
        let json = """
        {"formatVersion":1,"title":"旧","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[]}
        """
        let decoded = try FlorettaCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertTrue(decoded.freeNodes.isEmpty)
        XCTAssertTrue(decoded.relationships.isEmpty)
        let again = try XCTUnwrap(String(data: try FlorettaCodec.encode(decoded), encoding: .utf8))
        XCTAssertFalse(again.contains("\"freeNodes\""))
        XCTAssertFalse(again.contains("\"relationships\""))
        XCTAssertThrowsError(
            try FlorettaCodec.decode(Data(#"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"freeNodes":{}}"#.utf8))
        ) { error in
            guard case .corrupt(let message) = error as? FlorettaCodecError else {
                return XCTFail("expected corrupt, got \(error)")
            }
            XCTAssertTrue(message.contains("freeNodes"))
        }
    }

    func testDuplicateFreeNodeIDAndDanglingRelationshipAreRejected() {
        let shared = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let duplicate = MindMapDocument(
            title: "dup",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: shared, text: "根")],
            freeNodes: [MindMapNode(id: shared, text: "自由", position: MindMapPoint(x: 1, y: 2))]
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(duplicate)) { error in
            XCTAssertEqual(error as? FlorettaCodecError, .duplicateID(shared))
        }
        let missing = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let dangling = MindMapDocument(
            title: "miss",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "根")],
            relationships: [TopicRelationship(id: linkID, sourceID: rootID, targetID: missing)]
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(dangling)) { error in
            guard case .corrupt(let message) = error as? FlorettaCodecError else {
                return XCTFail("expected corrupt, got \(error)")
            }
            XCTAssertTrue(message.contains(linkID.uuidString))
        }
    }

    func testXMindExportMapsFreeNodesToDetachedTopicsWithoutLoss() throws {
        var document = MindMapDocument(
            title: "地图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "中心", children: [MindMapNode(text: "分支")])]
        )
        let hash = String(repeating: "c", count: 64)
        document.addFreeNode(
            text: "浮动",
            at: MindMapPoint(x: 12.5, y: -3),
            id: freeID,
            note: "备注",
            link: "https://example.com/a",
            attachments: [
                NodeAttachment(sha256: hash, fileExtension: "pdf", byteCount: 9, filename: "规格.pdf"),
            ]
        )
        var withChild = document.freeNodes[0]
        withChild.children = [MindMapNode(id: childID, text: "附在浮动上")]
        document.freeNodes[0] = withChild
        _ = document.linkTopics(from: freeID, to: rootID, title: "关联", id: linkID)

        let data = try FlorettaXMindCodec.export(document)
        let entries = try ZipArchive.read(data, limits: .standard)
        let content = try XCTUnwrap(entries.first { $0.name == "content.json" }?.data)
        let sheets = try XCTUnwrap(try JSONSerialization.jsonObject(with: content) as? [[String: Any]])
        XCTAssertEqual(sheets.count, 1)
        let root = try XCTUnwrap(sheets[0]["rootTopic"] as? [String: Any])
        let children = try XCTUnwrap(root["children"] as? [String: Any])
        let detached = try XCTUnwrap(children["detached"] as? [[String: Any]])
        XCTAssertEqual(detached.map { $0["id"] as? String }, [freeID.uuidString])
        let attached = children["attached"] as? [[String: Any]] ?? []
        XCTAssertFalse(attached.contains { ($0["id"] as? String) == freeID.uuidString })
        let position = try XCTUnwrap(detached[0]["position"] as? [String: Any])
        XCTAssertEqual((position["x"] as? NSNumber)?.doubleValue ?? -1, 12.5, accuracy: 0.001)
        XCTAssertEqual((position["y"] as? NSNumber)?.doubleValue ?? 1, -3, accuracy: 0.001)
        let relationships = try XCTUnwrap(sheets[0]["relationships"] as? [[String: Any]])
        XCTAssertEqual(relationships.first?["end1Id"] as? String, freeID.uuidString)
        XCTAssertEqual(relationships.first?["end2Id"] as? String, rootID.uuidString)
        XCTAssertEqual(relationships.first?["title"] as? String, "关联")

        let imported = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(imported.title, "地图")
        XCTAssertEqual(imported.roots.map(\.id), [rootID])
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["分支"])
        XCTAssertEqual(imported.freeNodes.map(\.id), [freeID])
        XCTAssertEqual(imported.freeNodes[0].text, "浮动")
        XCTAssertEqual(imported.freeNodes[0].position, MindMapPoint(x: 12.5, y: -3))
        XCTAssertEqual(imported.freeNodes[0].note, "备注")
        XCTAssertEqual(imported.freeNodes[0].link, "https://example.com/a")
        XCTAssertEqual(imported.freeNodes[0].attachments.map(\.filename), ["规格.pdf"])
        XCTAssertEqual(imported.freeNodes[0].children.map(\.id), [childID])
        XCTAssertEqual(imported.relationships, [
            TopicRelationship(id: linkID, sourceID: freeID, targetID: rootID, title: "关联"),
        ])
        XCTAssertNil(LayoutEngine().layout(imported).first { $0.id == childID })
        let placed = try XCTUnwrap(LayoutEngine().layout(imported).first { $0.id == freeID })
        XCTAssertEqual(placed.origin.x, 12.5, accuracy: 0.001)
        XCTAssertEqual(placed.origin.y, -3, accuracy: 0.001)
        XCTAssertNil(placed.link)
    }

    func testSeveralRootsKeepFreeNodesDetached() throws {
        var document = MindMapDocument(
            title: "多根",
            roots: [MindMapNode(id: rootID, text: "甲"), MindMapNode(id: otherID, text: "乙")]
        )
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 7, y: 8), id: freeID)
        let imported = try FlorettaXMindCodec.importMap(try FlorettaXMindCodec.export(document))
        XCTAssertEqual(imported.freeNodes.map(\.id), [freeID])
        XCTAssertEqual(imported.freeNodes[0].position, MindMapPoint(x: 7, y: 8))
        let rootIDs = imported.roots.flatMap { [$0.id] + $0.children.map(\.id) }
        XCTAssertFalse(rootIDs.contains(freeID))
        XCTAssertTrue(rootIDs.contains(rootID))
        XCTAssertTrue(rootIDs.contains(otherID))
    }

    func testFreeNodesCountTowardThePackageLimit() {
        var limits = ZipLimits.standard
        limits.maxNodes = 1
        var document = MindMapDocument(title: "限", roots: [MindMapNode(id: rootID, text: "根")])
        XCTAssertNoThrow(try ZipContainer(limits: limits).write(FlorettaPackage(document: document)))
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 1, y: 1), id: freeID)
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertThrowsError(try ZipContainer(limits: limits).write(FlorettaPackage(document: document)))
    }

    private func tree() -> MindMapDocument {
        MindMapDocument(
            title: "树",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "根")]
        )
    }

    private func assertKeyOrder(_ json: String, _ keys: [String]) throws {
        var lower = json.startIndex
        for key in keys {
            let needle = "\"\(key)\""
            let range = try XCTUnwrap(json.range(of: needle, range: lower..<json.endIndex), "missing \(needle)")
            lower = range.upperBound
        }
    }
}
