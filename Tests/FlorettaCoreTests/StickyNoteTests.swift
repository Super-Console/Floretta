import FlorettaCore
import XCTest

final class StickyNoteTests: XCTestCase {
    private let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let freeID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let stickyID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
    private let otherStickyID = UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testPaletteHasFiveColorsAndSizeIsCapped() {
        XCTAssertEqual(StickyColor.allCases, StickyColor.palette)
        XCTAssertEqual(StickyColor.palette.map(\.rawValue), ["yellow", "pink", "green", "blue", "orange"])

        var huge = StickyNote(text: "大", origin: MindMapPoint(x: 1, y: 2), width: 5_000, height: 9_000)
        XCTAssertEqual(huge.width, StickyLimits.maxWidth)
        XCTAssertEqual(huge.height, StickyLimits.maxHeight)
        let tiny = StickyNote(text: "小", origin: MindMapPoint(x: 1, y: 2), width: 1, height: 2)
        XCTAssertEqual(tiny.width, StickyLimits.minWidth)
        XCTAssertEqual(tiny.height, StickyLimits.minHeight)
        huge.width = .infinity
        XCTAssertEqual(huge.width, StickyLimits.defaultWidth)
    }

    func testStickyIsOutsideTheTreeAndDoesNotChangeLayout() throws {
        var document = tree()
        let before = LayoutEngine().layout(document)
        let added = document.addSticky(
            text: "买菜\n牛奶",
            color: .green,
            at: MindMapPoint(x: 40, y: -20),
            width: 10,
            height: 10,
            id: stickyID
        )
        XCTAssertEqual(added, stickyID)
        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertEqual(document.topicCount, 1)
        XCTAssertNil(document.node(stickyID))
        XCTAssertNil(document.parentID(of: stickyID))
        XCTAssertFalse(document.isFreeNode(stickyID))
        XCTAssertFalse(document.isInFreeNodeTree(stickyID))
        XCTAssertEqual(document.topics(matching: "买菜"), [])
        XCTAssertEqual(document.topics(matching: "根"), [rootID])
        XCTAssertNil(document.linkTopics(from: rootID, to: stickyID))
        XCTAssertFalse(document.insertChild(MindMapNode(text: "子"), under: stickyID))
        let sticky = try XCTUnwrap(document.sticky(stickyID))
        XCTAssertEqual(sticky.text, "买菜\n牛奶")
        XCTAssertEqual(sticky.color, .green)
        XCTAssertEqual(sticky.width, StickyLimits.minWidth)
        XCTAssertEqual(sticky.height, StickyLimits.minHeight)

        let frames = LayoutEngine().layout(document)
        XCTAssertNil(frames.first { $0.id == stickyID })
        XCTAssertEqual(frames.map(\.id), before.map(\.id))
        for original in before {
            let again = try XCTUnwrap(frames.first { $0.id == original.id })
            XCTAssertEqual(again.origin.x, original.origin.x, accuracy: 0.001)
            XCTAssertEqual(again.origin.y, original.origin.y, accuracy: 0.001)
            XCTAssertEqual(again.parentID, original.parentID)
        }
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document), [rootID])
    }

    func testStickyCoexistsWithFreeNodeAndAttachment() throws {
        var document = tree()
        let hash = String(repeating: "a", count: 64)
        document.roots[0].attachments = [
            NodeAttachment(sha256: hash, fileExtension: "psd", byteCount: 12, filename: "稿.psd"),
        ]
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 12, y: 8), id: freeID)
        document.addSticky(text: "便签不应进导出树", color: .orange, at: MindMapPoint(x: -30, y: 16), id: stickyID)
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertEqual(document.freeNodes.map(\.id), [freeID])
        XCTAssertEqual(document.stickies.map(\.id), [stickyID])
        XCTAssertEqual(AttachmentReferences.counts(in: document).map(\.sha256), [hash])
        XCTAssertEqual(document.topics(matching: "自由"), [freeID])
        XCTAssertEqual(document.topics(matching: "便签"), [])

        let frames = LayoutEngine().layout(document)
        let free = try XCTUnwrap(frames.first { $0.id == freeID })
        XCTAssertEqual(free.origin.x, 12, accuracy: 0.001)
        XCTAssertTrue(free.isFree)
        XCTAssertNil(frames.first { $0.id == stickyID })

        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.formatVersion, 1)

        let markdown = FlorettaMarkdown.export(document)
        XCTAssertFalse(markdown.contains("便签不应进导出树"))
        XCTAssertFalse(markdown.contains("自由"))
        let mm = try XCTUnwrap(String(data: try FlorettaMMCodec.export(document), encoding: .utf8))
        XCTAssertFalse(mm.contains("便签不应进导出树"))
        let opml = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(document), encoding: .utf8))
        XCTAssertFalse(opml.contains("便签不应进导出树"))

        let xmind = try FlorettaXMindCodec.export(document)
        let entries = try ZipArchive.read(xmind, limits: .standard)
        let content = try XCTUnwrap(entries.first { $0.name == "content.json" }?.data)
        let text = try XCTUnwrap(String(data: content, encoding: .utf8))
        XCTAssertFalse(text.contains("便签不应进导出树"))
        XCTAssertFalse(text.contains(stickyID.uuidString))
        XCTAssertTrue(text.contains(freeID.uuidString))
        let imported = try FlorettaXMindCodec.importMap(xmind)
        XCTAssertTrue(imported.stickies.isEmpty)
        XCTAssertEqual(imported.freeNodes.map(\.id), [freeID])
        XCTAssertEqual(imported.topicCount, 2)
    }

    func testPictureExportCanLeaveStickiesOut() {
        var document = tree()
        document.addSticky(text: "卡片", at: MindMapPoint(x: 1, y: 2), id: stickyID)
        XCTAssertEqual(document.stickiesForPictureExport().map(\.id), [stickyID])
        XCTAssertEqual(document.stickiesForPictureExport(included: true).map(\.text), ["卡片"])
        XCTAssertTrue(document.stickiesForPictureExport(included: false).isEmpty)
        XCTAssertEqual(document.topicCount, 1)
    }

    func testRoundTripOmitsEmptyStickiesAndKeepsVersionOne() throws {
        var document = tree()
        let bare = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(bare.contains("\"stickies\""))
        document.addSticky(text: "一行\n两行", color: .blue, at: MindMapPoint(x: 3.5, y: -1), width: 200, height: 100, id: stickyID)
        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        try assertKeyOrder(json, ["createdAt", "formatVersion", "modifiedAt", "roots", "stickies", "title"])
        XCTAssertEqual(document.formatVersion, 1)
        let decoded = try FlorettaCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.stickies[0].text, "一行\n两行")
        XCTAssertEqual(decoded.stickies[0].color, .blue)
        XCTAssertEqual(decoded.stickies[0].origin, MindMapPoint(x: 3.5, y: -1))
        XCTAssertEqual(decoded.stickies[0].width, 200)
        XCTAssertEqual(decoded.stickies[0].height, 100)
        XCTAssertFalse(json.contains("\"freeNodes\""))
    }

    func testOldFileOpensAndHostileStickyJSONIsRejected() throws {
        let old = """
        {"formatVersion":1,"title":"旧","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[]}
        """
        let decoded = try FlorettaCodec.decode(Data(old.utf8))
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertTrue(decoded.stickies.isEmpty)
        XCTAssertTrue(decoded.freeNodes.isEmpty)
        let again = try XCTUnwrap(String(data: try FlorettaCodec.encode(decoded), encoding: .utf8))
        XCTAssertFalse(again.contains("\"stickies\""))

        let oversized = """
        {"formatVersion":1,"title":"大","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"stickies":[{"id":"\(stickyID.uuidString)","text":"卡","color":"pink","origin":{"x":1,"y":2},"width":9999,"height":1}]}
        """
        let clamped = try FlorettaCodec.decode(Data(oversized.utf8))
        XCTAssertEqual(clamped.stickies[0].color, .pink)
        XCTAssertEqual(clamped.stickies[0].width, StickyLimits.maxWidth)
        XCTAssertEqual(clamped.stickies[0].height, StickyLimits.minHeight)

        assertCorrupt(
            #"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"stickies":{}}"#,
            containing: "stickies"
        )
        assertCorrupt(
            #"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"stickies":[{"id":"\#(stickyID.uuidString)","text":"卡","color":"purple","origin":{"x":1,"y":2},"width":160,"height":120}]}"#,
            containing: "purple"
        )
    }

    func testDuplicateStickyIDAndRelationshipToAStickyAreRejected() {
        let shared = MindMapDocument(
            title: "dup",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "根")],
            stickies: [StickyNote(id: rootID, text: "卡", origin: MindMapPoint(x: 1, y: 2))]
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(shared)) { error in
            XCTAssertEqual(error as? FlorettaCodecError, .duplicateID(rootID))
        }
        let twins = MindMapDocument(
            title: "twins",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "根")],
            stickies: [
                StickyNote(id: stickyID, text: "甲", origin: MindMapPoint(x: 1, y: 2)),
                StickyNote(id: stickyID, text: "乙", origin: MindMapPoint(x: 3, y: 4)),
            ]
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(twins)) { error in
            XCTAssertEqual(error as? FlorettaCodecError, .duplicateID(stickyID))
        }
        var linked = tree()
        linked.stickies = [StickyNote(id: stickyID, text: "卡", origin: MindMapPoint(x: 1, y: 2))]
        linked.relationships = [TopicRelationship(sourceID: rootID, targetID: stickyID)]
        XCTAssertThrowsError(try FlorettaCodec.encode(linked)) { error in
            guard case .corrupt(let message) = error as? FlorettaCodecError else {
                return XCTFail("expected corrupt, got \(error)")
            }
            XCTAssertTrue(message.contains(stickyID.uuidString), message)
            XCTAssertTrue(message.contains("missing topic"), message)
        }
    }

    func testStickiesDoNotCountTowardThePackageLimit() throws {
        var limits = ZipLimits.standard
        limits.maxNodes = 1
        var document = MindMapDocument(title: "限", roots: [MindMapNode(id: rootID, text: "根")])
        document.addSticky(text: "卡", at: MindMapPoint(x: 4, y: 5), id: stickyID)
        XCTAssertEqual(document.topicCount, 1)
        XCTAssertNoThrow(try ZipContainer(limits: limits).write(FlorettaPackage(document: document)))
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 1, y: 1), id: freeID)
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertThrowsError(try ZipContainer(limits: limits).write(FlorettaPackage(document: document)))
    }

    func testHitTestPrefersTheLaterStickyAndTheResizeCorner() {
        let under = StickyNote(id: stickyID, text: "下", origin: MindMapPoint(x: 0, y: 0), width: 200, height: 160)
        let over = StickyNote(id: otherStickyID, text: "上", origin: MindMapPoint(x: 40, y: 40), width: 200, height: 160)
        XCTAssertEqual(StickyGeometry.hit(x: 20, y: 20, in: [under, over]), .body(stickyID))
        XCTAssertEqual(StickyGeometry.hit(x: 50, y: 50, in: [under, over]), .body(otherStickyID))
        let cornerX = over.origin.x + over.width - 1
        let cornerY = over.origin.y + over.height - 1
        XCTAssertEqual(StickyGeometry.hit(x: cornerX, y: cornerY, in: [under, over]), .resize(otherStickyID))
        XCTAssertNil(StickyGeometry.hit(x: -1, y: -1, in: [under, over]))
        XCTAssertFalse(documentPlaceAllowsANonFiniteOrigin())
    }

    func testUndoRedoCoversCreateEditMoveResizeDeleteAndColor() throws {
        var document = tree()
        var session = MindMapKeyboardSession()
        let id = try XCTUnwrap(session.addSticky(
            at: MindMapPoint(x: 8, y: 9),
            color: .yellow,
            text: "原来",
            document: &document
        ))
        XCTAssertEqual(session.selectedStickyID, id)
        XCTAssertNil(session.selectedNodeID)
        XCTAssertEqual(document.topicCount, 1)
        XCTAssertTrue(document.roots[0].children.isEmpty)

        session.apply(.createChild, document: &document, frames: [])
        session.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.stickies.isEmpty)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.stickies.map(\.id), [id])
        XCTAssertEqual(session.selectedStickyID, id)

        session.apply(.beginEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .edit)
        session.replaceEditingText("第一行\n第二行", document: &document)
        session.apply(.insertNewline, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.text, "第一行\n第二行\n")
        session.apply(.commitEdit, document: &document, frames: [])
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.text, "原来")
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.text, "第一行\n第二行\n")

        XCTAssertTrue(session.moveSticky(id, to: MindMapPoint(x: 30, y: -4), document: &document))
        XCTAssertEqual(document.sticky(id)?.origin, MindMapPoint(x: 30, y: -4))
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.origin, MindMapPoint(x: 8, y: 9))
        session.apply(.redo, document: &document, frames: [])

        XCTAssertTrue(session.resizeSticky(id, width: 9_000, height: 10, document: &document))
        XCTAssertEqual(document.sticky(id)?.width, StickyLimits.maxWidth)
        XCTAssertEqual(document.sticky(id)?.height, StickyLimits.minHeight)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.width, StickyLimits.defaultWidth)
        XCTAssertEqual(document.sticky(id)?.height, StickyLimits.defaultHeight)
        session.apply(.redo, document: &document, frames: [])

        XCTAssertTrue(session.setStickyColor(.pink, id: id, document: &document))
        XCTAssertEqual(document.sticky(id)?.color, .pink)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.color, .yellow)
        session.apply(.redo, document: &document, frames: [])

        session.selectedStickyID = id
        session.apply(.deleteSelection, document: &document, frames: [])
        XCTAssertTrue(document.stickies.isEmpty)
        XCTAssertEqual(document.topicCount, 1)
        XCTAssertEqual(document.roots.map(\.id), [rootID])
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.stickies.map(\.id), [id])
        XCTAssertEqual(document.sticky(id)?.color, .pink)
        XCTAssertEqual(session.selectedStickyID, id)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertTrue(document.stickies.isEmpty)
    }

    func testOneDragIsOneUndoStep() {
        var document = tree()
        var session = MindMapKeyboardSession()
        let id = session.addSticky(at: MindMapPoint(x: 0, y: 0), document: &document)!
        session.beginStickyChange(document: document)
        XCTAssertTrue(document.placeSticky(id, origin: MindMapPoint(x: 10, y: 0), width: 200, height: 140))
        XCTAssertTrue(document.placeSticky(id, origin: MindMapPoint(x: 24, y: 6), width: 240, height: 150))
        session.commitStickyChange(document: document)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.origin, MindMapPoint(x: 0, y: 0))
        XCTAssertEqual(document.sticky(id)?.width, StickyLimits.defaultWidth)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.sticky(id)?.origin, MindMapPoint(x: 24, y: 6))
        XCTAssertEqual(document.sticky(id)?.width, 240)
        XCTAssertEqual(document.sticky(id)?.height, 150)
        XCTAssertEqual(document.topicCount, 1)
    }

    private func tree() -> MindMapDocument {
        MindMapDocument(
            title: "树",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: rootID, text: "根")]
        )
    }

    private func documentPlaceAllowsANonFiniteOrigin() -> Bool {
        var document = tree()
        document.addSticky(at: MindMapPoint(x: 0, y: 0), id: stickyID)
        return document.placeSticky(
            stickyID,
            origin: MindMapPoint(x: .nan, y: 1),
            width: 160,
            height: 120
        )
    }

    private func assertCorrupt(_ json: String, containing needle: String) {
        XCTAssertThrowsError(try FlorettaCodec.decode(Data(json.utf8))) { error in
            guard case .corrupt(let message) = error as? FlorettaCodecError else {
                return XCTFail("expected corrupt, got \(error)")
            }
            XCTAssertTrue(message.contains(needle), message)
        }
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
