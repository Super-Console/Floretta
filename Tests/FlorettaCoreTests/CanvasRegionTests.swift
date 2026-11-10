import XCTest
import FlorettaCore

final class CanvasRegionTests: XCTestCase {
    private let regionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let stamped = ISO8601DateFormatter().date(from: "2026-11-10T00:00:00Z")!

    func testTypedSizeRespectsTheLockAndTheCaps() {
        var region = CanvasRegion(id: regionID, label: "区", origin: MindMapPoint(x: 8, y: 12), width: 200, height: 100)
        region.aspectLocked = true
        let wider = CanvasRegionGeometry.typed(
            width: region.width,
            height: region.height,
            axis: .width,
            value: 400,
            locked: region.aspectLocked
        )
        XCTAssertEqual(wider.width, 400, accuracy: 0.001)
        XCTAssertEqual(wider.height, 200, accuracy: 0.001)

        let shorter = CanvasRegionGeometry.typed(
            width: wider.width,
            height: wider.height,
            axis: .height,
            value: 50,
            locked: true
        )
        XCTAssertEqual(shorter.height, 50, accuracy: 0.001)
        XCTAssertEqual(shorter.width, 100, accuracy: 0.001)

        let unlocked = CanvasRegionGeometry.typed(
            width: shorter.width,
            height: shorter.height,
            axis: .width,
            value: 80,
            locked: false
        )
        XCTAssertEqual(unlocked.width, 80, accuracy: 0.001)
        XCTAssertEqual(unlocked.height, 50, accuracy: 0.001)

        let huge = CanvasRegion(label: "大", origin: MindMapPoint(x: 0, y: 0), width: 20_000, height: 1)
        XCTAssertEqual(huge.width, CanvasRegionLimits.maxWidth)
        XCTAssertEqual(huge.height, CanvasRegionLimits.minHeight)
        var stroked = huge
        stroked.strokeWidth = 80
        XCTAssertEqual(stroked.strokeWidth, CanvasRegionLimits.maxStroke)
        stroked.strokeWidth = -4
        XCTAssertEqual(stroked.strokeWidth, CanvasRegionLimits.minStroke)
    }

    func testResizeKeepsTheLockedRatio() {
        let size = CanvasRegionGeometry.resized(width: 200, height: 100, dx: 50, dy: 10, locked: true)
        XCTAssertEqual(size.width, 250, accuracy: 0.001)
        XCTAssertEqual(size.height, 125, accuracy: 0.001)
        let free = CanvasRegionGeometry.resized(width: 200, height: 100, dx: 50, dy: 10, locked: false)
        XCTAssertEqual(free.width, 250, accuracy: 0.001)
        XCTAssertEqual(free.height, 110, accuracy: 0.001)
    }

    func testCircleCentersAOneToOneEllipseAndLocksTheAspect() throws {
        var document = sample()
        let id = try XCTUnwrap(document.addRegion(
            label: "圆",
            at: MindMapPoint(x: 10, y: 20),
            width: 120,
            height: 80,
            id: regionID
        ))
        XCTAssertTrue(document.makeRegionCircle(id))
        let region = try XCTUnwrap(document.region(id))
        XCTAssertEqual(region.shape, .ellipse)
        XCTAssertTrue(region.aspectLocked)
        XCTAssertEqual(region.width, 120, accuracy: 0.001)
        XCTAssertEqual(region.height, 120, accuracy: 0.001)
        XCTAssertEqual(region.origin.x, 10, accuracy: 0.001)
        XCTAssertEqual(region.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(document.roots, sample().roots)
    }

    func testFitUsesOnlyFullyEnclosedNodesAndDoesNotReparent() throws {
        var document = sample()
        let childBefore = document.parentID(of: childID)
        let rootsBefore = document.roots
        let freeBefore = document.freeNodes
        let id = try XCTUnwrap(document.addRegion(
            at: MindMapPoint(x: 0, y: 0),
            width: 400,
            height: 300,
            id: regionID
        ))
        let enclosed = CGRect(x: 40, y: 50, width: 80, height: 30)
        let partial = CGRect(x: 380, y: 10, width: 50, height: 20)
        let outside = CGRect(x: 500, y: 500, width: 20, height: 20)
        let frames = [
            nodeFrame(id: childID, rect: enclosed),
            nodeFrame(id: rootID, rect: partial),
            nodeFrame(id: UUID(), rect: outside),
        ]
        XCTAssertTrue(document.fitRegion(id, to: frames))
        let region = try XCTUnwrap(document.region(id))
        XCTAssertEqual(region.origin.x, 16, accuracy: 0.001)
        XCTAssertEqual(region.origin.y, 26, accuracy: 0.001)
        XCTAssertEqual(region.width, 128, accuracy: 0.001)
        XCTAssertEqual(region.height, 78, accuracy: 0.001)
        XCTAssertEqual(document.roots, rootsBefore)
        XCTAssertEqual(document.freeNodes, freeBefore)
        XCTAssertEqual(document.parentID(of: childID), childBefore)
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertNotEqual(document.region(id)?.id, childID)

        document.setRegionAspectLocked(id, true)
        document.placeRegion(id, origin: MindMapPoint(x: 0, y: 0), width: 400, height: 300)
        XCTAssertTrue(document.fitRegion(id, to: frames))
        let locked = try XCTUnwrap(document.region(id))
        XCTAssertEqual(locked.width, 128, accuracy: 0.001)
        XCTAssertEqual(locked.height, 96, accuracy: 0.001)
        XCTAssertEqual(locked.origin.x, 16, accuracy: 0.001)
        XCTAssertEqual(locked.origin.y, 17, accuracy: 0.001)
        XCTAssertEqual(document.roots, rootsBefore)

        document.placeRegion(id, origin: MindMapPoint(x: 0, y: 0), width: 40, height: 40)
        XCTAssertFalse(document.fitRegion(id, to: [nodeFrame(id: childID, rect: enclosed)]))
        XCTAssertEqual(document.region(id)?.width, CanvasRegionLimits.minWidth)
        XCTAssertEqual(document.roots, rootsBefore)
    }

    func testPersistenceRoundTripsStyleAndLeavesOldFilesAlone() throws {
        var document = sample()
        let bare = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(bare.contains("\"regions\""))
        XCTAssertEqual(document.formatVersion, 1)

        let id = try XCTUnwrap(document.addRegion(label: "一片\n区域", at: MindMapPoint(x: 3.5, y: -1), width: 240, height: 120, id: regionID))
        document.setRegionAspectLocked(id, true)
        document.setRegionShape(id, .ellipse)
        XCTAssertTrue(document.setRegionFill(id, BranchColor(hex: "#112233")!))
        XCTAssertTrue(document.setRegionBorder(id, BranchColor(hex: "#ABCDEF")!))
        document.setRegionStrokeWidth(id, 6)

        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        let region = try XCTUnwrap(decoded.region(regionID))
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(region.label, "一片\n区域")
        XCTAssertEqual(region.origin, MindMapPoint(x: 3.5, y: -1))
        XCTAssertEqual(region.width, 240)
        XCTAssertEqual(region.height, 120)
        XCTAssertTrue(region.aspectLocked)
        XCTAssertEqual(region.shape, .ellipse)
        XCTAssertEqual(region.fill.hexRGB, "#112233")
        XCTAssertEqual(region.border.hexRGB, "#ABCDEF")
        XCTAssertEqual(region.strokeWidth, 6)
        XCTAssertEqual(decoded.roots, document.roots)

        let old = """
        {"formatVersion":1,"title":"旧","createdAt":"2026-11-10T00:00:00Z","modifiedAt":"2026-11-10T00:00:00Z","roots":[]}
        """
        let opened = try FlorettaCodec.decode(Data(old.utf8))
        XCTAssertTrue(opened.regions.isEmpty)
        let again = try XCTUnwrap(String(data: try FlorettaCodec.encode(opened), encoding: .utf8))
        XCTAssertFalse(again.contains("\"regions\""))

        let minimal = """
        {"formatVersion":1,"title":"少","createdAt":"2026-11-10T00:00:00Z","modifiedAt":"2026-11-10T00:00:00Z","roots":[],"regions":[{"id":"\(regionID.uuidString)","origin":{"x":1,"y":2},"width":180,"height":90}]}
        """
        let filled = try FlorettaCodec.decode(Data(minimal.utf8))
        XCTAssertEqual(filled.regions[0].shape, .rectangle)
        XCTAssertFalse(filled.regions[0].aspectLocked)
        XCTAssertEqual(filled.regions[0].fill.hexRGB, CanvasRegionLimits.defaultFill.hexRGB)
        XCTAssertEqual(filled.regions[0].strokeWidth, CanvasRegionLimits.defaultStroke)

        assertCorrupt(
            #"{"formatVersion":1,"title":"t","createdAt":"2026-11-10T00:00:00Z","modifiedAt":"2026-11-10T00:00:00Z","roots":[],"regions":{}}"#,
            containing: "regions"
        )
        assertCorrupt(
            #"{"formatVersion":1,"title":"t","createdAt":"2026-11-10T00:00:00Z","modifiedAt":"2026-11-10T00:00:00Z","roots":[],"regions":[{"id":"\#(regionID.uuidString)","origin":{"x":1,"y":2},"width":180,"height":90,"shape":"triangle"}]}"#,
            containing: "triangle"
        )
    }

    func testARegionIsNotATopicAndDoesNotEnterOtherFormats() throws {
        var document = sample()
        document.addRegion(label: "专区标签不进导出", at: MindMapPoint(x: 4, y: 8), id: regionID)
        XCTAssertEqual(document.topicCount, 2)
        XCTAssertEqual(document.topics(matching: "专区"), [])
        XCTAssertNil(LayoutEngine().layout(document).first { $0.id == regionID })

        let markdown = FlorettaMarkdown.export(document)
        XCTAssertFalse(markdown.contains("专区标签不进导出"))
        let asDocument = FlorettaMarkdownDocumentCodec.save(document)
        XCTAssertFalse(asDocument.contains("专区标签不进导出"))
        let mm = try XCTUnwrap(String(data: try FlorettaMMCodec.export(document), encoding: .utf8))
        XCTAssertFalse(mm.contains("专区标签不进导出"))
        let opml = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(document), encoding: .utf8))
        XCTAssertFalse(opml.contains("专区标签不进导出"))
        let xmind = try FlorettaXMindCodec.export(document)
        let entries = try ZipArchive.read(xmind, limits: .standard)
        let content = try XCTUnwrap(entries.first { $0.name == "content.json" }?.data)
        let text = try XCTUnwrap(String(data: content, encoding: .utf8))
        XCTAssertFalse(text.contains("专区标签不进导出"))
        XCTAssertFalse(text.contains(regionID.uuidString))
        let imported = try FlorettaXMindCodec.importMap(xmind)
        XCTAssertTrue(imported.regions.isEmpty)
        XCTAssertEqual(imported.topicCount, 2)
    }

    func testOPMLUnknownFieldsSurviveWhenARegionIsAdded() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>T</title><ownerName>kept-owner</ownerName></head>
          <body><outline text="根" customFlag="keep-me"/></body>
        </opml>
        """
        let data = Data(xml.utf8)
        var document = try FlorettaOPMLCodec.importOutline(data)
        document.addRegion(label: "专区留在工程里", at: MindMapPoint(x: 1, y: 2), id: regionID)
        let untouched = try FlorettaOPMLCodec.export(document)
        XCTAssertEqual(untouched, data)
        let stored = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(stored.regions.map(\.id), [regionID])
        XCTAssertEqual(try FlorettaOPMLCodec.export(stored), data)

        var edited = stored
        edited.roots[0].text = "改过"
        let rewritten = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(edited), encoding: .utf8))
        XCTAssertTrue(rewritten.contains("customFlag=\"keep-me\""))
        XCTAssertTrue(rewritten.contains("ownerName"))
        XCTAssertFalse(rewritten.contains("专区留在工程里"))
        XCTAssertFalse(rewritten.contains(regionID.uuidString))
    }

    func testDuplicateRegionIDIsRejectedAndUndoRestoresTheZone() throws {
        var shared = sample()
        XCTAssertNil(shared.addRegion(at: MindMapPoint(x: 1, y: 2), id: rootID))
        shared.regions = [CanvasRegion(id: rootID, origin: MindMapPoint(x: 1, y: 2))]
        XCTAssertThrowsError(try FlorettaCodec.encode(shared)) { error in
            XCTAssertEqual(error as? FlorettaCodecError, .duplicateID(rootID))
        }

        var document = sample()
        var keyboard = MindMapKeyboardSession()
        let id = try XCTUnwrap(keyboard.addRegion(at: MindMapPoint(x: 12, y: 18), label: "可撤销", document: &document))
        XCTAssertEqual(keyboard.selectedRegionID, id)
        XCTAssertNil(keyboard.selectedNodeID)
        keyboard.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.regions.isEmpty)
        XCTAssertEqual(document.roots, sample().roots)
        keyboard.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.regions.map(\.label), ["可撤销"])
        XCTAssertEqual(document.parentID(of: childID), rootID)
    }

    func testSelectionToolbarIsDeclaredOnTheSharedCanvas() throws {
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        let toolbar = try slice(canvas, from: "private var regionToolbar", until: "private var regionEditor")
        XCTAssertTrue(toolbar.contains("selectedRegionID"))
        XCTAssertTrue(toolbar.contains("text(\"锁定\")"))
        XCTAssertTrue(toolbar.contains("accessibilityIdentifier(\"region.lock\")"))
        XCTAssertTrue(toolbar.contains("text(\"适应\")"))
        XCTAssertTrue(toolbar.contains("accessibilityIdentifier(\"region.fit\")"))
        XCTAssertTrue(toolbar.contains("text(\"圆形\")"))
        XCTAssertTrue(toolbar.contains("accessibilityIdentifier(\"region.circle\")"))
        XCTAssertTrue(canvas.contains("updateRegionDrag"))
        XCTAssertTrue(canvas.contains("DragGesture(minimumDistance: 2)"))
        // Petal expand (#84) uses a paused TimelineView for playback. Region
        // drag and the selection toolbar must not hitch a ride on that clock.
        XCTAssertFalse(toolbar.contains("TimelineView"))

        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"region.width\")"))
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"region.height\")"))
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"region.stroke\")"))
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"region.label\")"))
        XCTAssertTrue(editor.contains("\"px\""))

        let project = try repoFile("Floretta.xcodeproj/project.pbxproj")
        XCTAssertGreaterThanOrEqual(project.components(separatedBy: "InfiniteCanvas.swift in Sources").count - 1, 2)
        XCTAssertGreaterThanOrEqual(project.components(separatedBy: "DocumentEditor.swift in Sources").count - 1, 2)
    }

    private func sample() -> MindMapDocument {
        var root = MindMapNode(id: rootID, text: "根")
        root.children = [MindMapNode(id: childID, text: "子")]
        return MindMapDocument(title: "图", createdAt: stamped, modifiedAt: stamped, roots: [root])
    }

    private func nodeFrame(id: UUID, rect: CGRect) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "框",
            origin: rect.origin,
            size: rect.size,
            depth: 1,
            fontSize: 16,
            isRoot: false,
            fill: .white,
            border: .black,
            textColor: .black,
            cornerRadius: 8
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

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}
