import XCTest
@testable import FlorettaCore

final class CanvasSheetTests: XCTestCase {
    func testAddingASecondCanvasKeepsTheFirstAndSelectsTheNewOne() {
        var document = MindMapDocument(title: "甲", roots: [MindMapNode(text: "第一")])
        let firstID = document.roots[0].id
        let index = document.addCanvas()
        XCTAssertEqual(index, 1)
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.clampedCanvasIndex, 1)
        XCTAssertEqual(document.canvasTitle(at: 1), "新画布")
        XCTAssertEqual(document.roots.map(\.id), [firstID])
        XCTAssertEqual(document.roots[0].text, "第一")
        XCTAssertEqual(document.additionalCanvases[0].roots.map(\.text), ["中心"])
        XCTAssertNotEqual(document.additionalCanvases[0].roots[0].id, firstID)

        document.renameCanvas(at: 1, to: "  乙页  ")
        XCTAssertEqual(document.canvasTitle(at: 1), "乙页")
        document.renameCanvas(at: 0, to: "甲页")
        XCTAssertEqual(document.title, "甲")
        XCTAssertEqual(document.canvasTitle(at: 0), "甲页")
        document.renameCanvas(at: 1, to: "   ")
        XCTAssertEqual(document.canvasTitle(at: 1), "乙页")
    }

    func testNodesAndZoomStayOnTheirOwnCanvas() {
        var document = MindMapDocument(title: "甲", roots: [MindMapNode(text: "第一")])
        let firstID = document.roots[0].id
        document.addCanvas()
        let secondID = document.additionalCanvases[0].roots[0].id
        var surface = document.isolatedCanvas(at: 1)
        surface.roots[0].text = "第二"
        surface.roots[0].children = [MindMapNode(text: "第二的子")]
        let stickyID = UUID()
        surface.stickies = [StickyNote(id: stickyID, text: "只在第二张", origin: MindMapPoint(x: 4, y: 5))]
        document.replaceCanvasContent(at: 1, with: surface)
        document.setViewport(CanvasViewportState(scale: 2, offsetX: 12, offsetY: -3), forCanvas: 0)
        document.setViewport(CanvasViewportState(scale: 0.5, offsetX: -8, offsetY: 6), forCanvas: 1)

        XCTAssertEqual(document.roots.map(\.text), ["第一"])
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertTrue(document.stickies.isEmpty)
        XCTAssertEqual(document.additionalCanvases[0].roots[0].text, "第二")
        XCTAssertEqual(document.additionalCanvases[0].roots[0].children.map(\.text), ["第二的子"])
        XCTAssertEqual(document.additionalCanvases[0].stickies.map(\.id), [stickyID])
        XCTAssertEqual(document.viewport(forCanvas: 0), CanvasViewportState(scale: 2, offsetX: 12, offsetY: -3))
        XCTAssertEqual(document.viewport(forCanvas: 1), CanvasViewportState(scale: 0.5, offsetX: -8, offsetY: 6))
        XCTAssertEqual(document.node(secondID)?.text, "第二")
        XCTAssertTrue(document.mutateNode(secondID) { $0.text = "改过的第二" })
        XCTAssertEqual(document.roots[0].text, "第一")
        XCTAssertEqual(document.node(firstID)?.text, "第一")

        let visible = document.isolatedCanvas(at: document.clampedCanvasIndex)
        XCTAssertTrue(visible.additionalCanvases.isEmpty)
        XCTAssertEqual(visible.roots.map(\.text), ["改过的第二"])
        let frames = LayoutEngine().layout(visible)
        XCTAssertTrue(frames.map(\.id).contains(secondID))
        XCTAssertFalse(frames.map(\.id).contains(firstID))
    }

    func testSaveAndOpenKeepsEveryCanvasTheActiveTabAndZoom() throws {
        var document = MindMapDocument(
            title: "甲",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            roots: [MindMapNode(text: "第一")]
        )
        document.addCanvas()
        document.renameCanvas(at: 0, to: "甲页")
        var surface = document.isolatedCanvas(at: 1)
        surface.roots[0].text = "第二"
        document.replaceCanvasContent(at: 1, with: surface)
        document.setViewport(CanvasViewportState(scale: 1.5, offsetX: 20, offsetY: 0), forCanvas: 0)
        document.setViewport(CanvasViewportState(scale: 3, offsetX: 0, offsetY: 9), forCanvas: 1)
        XCTAssertEqual(document.clampedCanvasIndex, 1)

        let opened = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(opened.canvasCount, 2)
        XCTAssertEqual(opened.clampedCanvasIndex, 1)
        XCTAssertEqual(opened.canvasTitle(at: 0), "甲页")
        XCTAssertEqual(opened.title, "甲")
        XCTAssertEqual(opened.roots.map(\.text), ["第一"])
        XCTAssertEqual(opened.additionalCanvases.map(\.title), ["新画布"])
        XCTAssertEqual(opened.additionalCanvases[0].roots.map(\.text), ["第二"])
        XCTAssertEqual(opened.viewport(forCanvas: 0).scale, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(opened.viewport(forCanvas: 0).offsetX, 20, accuracy: 0.000_1)
        XCTAssertEqual(opened.viewport(forCanvas: 1).scale, 3, accuracy: 0.000_1)
        XCTAssertEqual(opened.viewport(forCanvas: 1).offsetY, 9, accuracy: 0.000_1)

        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(opened), encoding: .utf8))
        XCTAssertTrue(json.contains("activeCanvasIndex"))
        XCTAssertTrue(json.contains("primaryCanvasTitle"))
        XCTAssertTrue(json.contains("primaryCanvasViewport"))
        XCTAssertTrue(json.contains("additionalCanvases"))
    }

    func testLegacySingleCanvasFileStillLoadsWithoutNewKeys() throws {
        let legacy = Data(
            #"{"formatVersion":1,"title":"旧","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","text":"根","note":"","collapsed":false,"children":[]}]}"#
                .utf8
        )
        let opened = try FlorettaCodec.decode(legacy)
        XCTAssertEqual(opened.canvasCount, 1)
        XCTAssertEqual(opened.clampedCanvasIndex, 0)
        XCTAssertEqual(opened.canvasTitle(at: 0), "旧")
        XCTAssertEqual(opened.roots.map(\.text), ["根"])
        XCTAssertTrue(opened.additionalCanvases.isEmpty)
        XCTAssertTrue(opened.viewport(forCanvas: 0).isStandard)
        XCTAssertNil(opened.primaryCanvasTitle)

        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(opened), encoding: .utf8))
        XCTAssertFalse(json.contains("activeCanvasIndex"))
        XCTAssertFalse(json.contains("primaryCanvasTitle"))
        XCTAssertFalse(json.contains("primaryCanvasViewport"))
        XCTAssertFalse(json.contains("additionalCanvases"))
        XCTAssertEqual(try FlorettaCodec.decode(Data(json.utf8)).roots.map(\.text), ["根"])

        let wildIndex = Data(
            #"{"formatVersion":1,"title":"旧","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"activeCanvasIndex":4}"#
                .utf8
        )
        let clamped = try FlorettaCodec.decode(wildIndex)
        XCTAssertEqual(clamped.canvasCount, 1)
        XCTAssertEqual(clamped.clampedCanvasIndex, 0)
    }

    func testNativeSaveKeepsCanvasesAndSingleTreeExportsNameTheActiveOne() throws {
        var document = MindMapDocument(title: "甲", roots: [MindMapNode(text: "只有第一")])
        document.addCanvas()
        var surface = document.isolatedCanvas(at: 1)
        surface.roots[0].text = "只有第二"
        document.replaceCanvasContent(at: 1, with: surface)
        let before = document

        let markdown = FlorettaMarkdown.export(document)
        let opml = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(document), encoding: .utf8))
        let mm = try XCTUnwrap(String(data: try FlorettaMMCodec.export(document), encoding: .utf8))
        let bundle = FlorettaTextBundleCodec.export(document)
        let markdownDocument = FlorettaMarkdownDocumentCodec.save(document)
        XCTAssertEqual(document, before)
        for text in [markdown, opml, mm, markdownDocument, String(data: bundle.data(at: "text.md") ?? Data(), encoding: .utf8)] {
            let rendered = try XCTUnwrap(text)
            XCTAssertTrue(rendered.contains("只有第二"), rendered)
            XCTAssertFalse(rendered.contains("只有第一"), rendered)
        }

        document.selectCanvas(0)
        let firstOnly = FlorettaMarkdown.export(document)
        XCTAssertTrue(firstOnly.contains("只有第一"))
        XCTAssertFalse(firstOnly.contains("只有第二"))
        XCTAssertEqual(document.canvasCount, 2)
        XCTAssertEqual(document.singleTreeExport().canvasCount, 2)
        XCTAssertEqual(document.singleTreeExport().roots.map(\.text), ["只有第一"])

        let xmind = try FlorettaXMindCodec.export(before)
        XCTAssertEqual(document.canvasCount, 2)
        let entries = try ZipArchive.read(xmind, limits: .standard)
        let content = try XCTUnwrap(entries.first { $0.name == "content.json" }?.data)
        let sheets = try XCTUnwrap(try JSONSerialization.jsonObject(with: content) as? [[String: Any]])
        XCTAssertEqual(sheets.count, 2)
        XCTAssertEqual(sheets.map { $0["title"] as? String }, ["甲", "新画布"])
        let imported = try FlorettaXMindCodec.importMap(xmind)
        XCTAssertEqual(imported.roots.map(\.text), ["只有第一"])
        XCTAssertEqual(imported.additionalCanvases.map(\.title), ["新画布"])
        XCTAssertEqual(imported.additionalCanvases[0].roots.map(\.text), ["只有第二"])
        XCTAssertEqual(before.canvasCount, 2)
    }

    func testPictureExportIsWiredToTheActiveCanvasAndLaterSheetsAreNotOrphans() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Floretta/Shared/Canvas/MapExport.swift"), encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "document.singleTreeExport()").count, 3)

        var document = MindMapDocument(title: "甲", roots: [MindMapNode(text: "第一")])
        document.addCanvas()
        let hash = String(repeating: "ab", count: 32)
        var surface = document.isolatedCanvas(at: 1)
        surface.roots[0].attachments = [
            NodeAttachment(sha256: hash, fileExtension: "png", byteCount: 4, filename: "sheet.png"),
        ]
        document.replaceCanvasContent(at: 1, with: surface)
        let stored = ZipStoredEntry(
            name: "assets/\(hash).png",
            method: 0,
            crc32: 0,
            byteCount: 4,
            localHeaderOffset: 0,
            dataOffset: 0
        )
        XCTAssertTrue(AttachmentReferences.orphans(stored: [stored], document: document).isEmpty)
        XCTAssertTrue(ImageAttachments.contains(document))
        let active = document.singleTreeExport()
        XCTAssertEqual(active.roots[0].attachments.map(\.filename), ["sheet.png"])
        XCTAssertTrue(active.additionalCanvases.isEmpty)
        document.selectCanvas(0)
        XCTAssertEqual(document.singleTreeExport().canvasCount, document.canvasCount)
        XCTAssertEqual(document.singleTreeExport().roots.map(\.text), ["第一"])
    }

    func testAStickyOnTheSecondCanvasCannotReuseAnIdentifier() {
        let shared = UUID()
        var document = MindMapDocument(title: "甲", roots: [MindMapNode(id: shared, text: "第一")])
        document.additionalCanvases = [
            MindMapCanvas(
                title: "乙",
                roots: [MindMapNode(text: "第二")],
                stickies: [StickyNote(id: shared, text: "撞了", origin: MindMapPoint(x: 0, y: 0))]
            ),
        ]
        XCTAssertThrowsError(try FlorettaCodec.encode(document)) { error in
            guard case FlorettaCodecError.duplicateID(shared) = error else {
                return XCTFail("\(error)")
            }
        }
    }
}
