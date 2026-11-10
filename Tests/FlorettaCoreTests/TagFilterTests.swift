import FlorettaCore
import XCTest

final class TagFilterTests: XCTestCase {
    func testLabelsStayOnTheTopicAndRoundTripInFlorettaJSON() throws {
        let id = UUID()
        var document = MindMapDocument(title: "t", roots: [MindMapNode(id: id, text: "根")])
        let bare = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(bare.contains("\"labels\""))
        XCTAssertFalse(bare.contains("\"markers\""))

        XCTAssertTrue(document.replaceLabels([" 想法 ", "想法", " "], on: id))
        XCTAssertTrue(document.setMarker("priority-1", in: .priority, on: id))
        XCTAssertTrue(document.setMarker("flag-red", in: .flag, on: id))
        XCTAssertEqual(document.node(id)?.labels, ["想法"])
        XCTAssertEqual(document.node(id)?.markers.map(\.markerId), ["priority-1", "flag-red"])

        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded.node(id)?.labels, ["想法"])
        XCTAssertEqual(decoded.node(id)?.markers.map(\.markerId), ["priority-1", "flag-red"])

        let legacy = Data(#"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[{"id":"\#(id.uuidString)","text":"根","note":"","collapsed":false,"children":[]}]}"#.utf8)
        let old = try FlorettaCodec.decode(legacy)
        XCTAssertEqual(old.node(id)?.labels, [])
        XCTAssertEqual(old.node(id)?.markers, [])
    }

    func testMarkerEditKeepsUnknownIdsAndReplacesOnlyItsGroup() {
        var markers = [
            TopicMarker(markerId: "star-red"),
            TopicMarker(markerId: "priority-2"),
        ]
        markers = TopicMarkerCatalog.assign(markers, markerID: "priority-1", group: .priority)
        XCTAssertEqual(markers.map(\.markerId), ["star-red", "priority-1"])
        markers = TopicMarkerCatalog.assign(markers, markerID: "flag-blue", group: .flag)
        XCTAssertEqual(markers.map(\.markerId), ["star-red", "priority-1", "flag-blue"])
        markers = TopicMarkerCatalog.assign(markers, markerID: "task-done", group: .priority)
        XCTAssertEqual(markers.map(\.markerId), ["star-red", "priority-1", "flag-blue"])
        markers = TopicMarkerCatalog.assign(markers, markerID: nil, group: .priority)
        XCTAssertEqual(markers.map(\.markerId), ["star-red", "flag-blue"])
        XCTAssertEqual(TopicMarkerCatalog.priorityNumber("priority-9"), 9)
        XCTAssertEqual(TopicMarkerCatalog.progressFraction("task-half"), 0.5)
        XCTAssertNil(TopicMarkerCatalog.group(of: "star-red"))
    }

    func testSearchAndFilterUseLabelsAndMarkersOnTheFirstSheet() throws {
        let root = UUID()
        let tagged = UUID()
        let free = UUID()
        let document = MindMapDocument(
            title: "t",
            roots: [
                MindMapNode(
                    id: root,
                    text: "根",
                    children: [
                        MindMapNode(
                            id: tagged,
                            text: "分支",
                            labels: ["想法"],
                            markers: [TopicMarker(markerId: "priority-1")]
                        ),
                    ]
                ),
            ],
            freeNodes: [
                MindMapNode(id: free, text: "自由", labels: ["想法"]),
            ]
        )
        XCTAssertEqual(document.topics(matching: "想法"), [tagged, free])
        XCTAssertEqual(document.topics(matching: "priority-1"), [])
        XCTAssertEqual(document.topics(matching: "分支"), [tagged])

        let off = TopicTagFilter()
        XCTAssertFalse(off.isActive)
        XCTAssertTrue(off.highlightedIDs(in: document).isEmpty)
        XCTAssertTrue(off.matches(document.roots[0]))

        let byLabel = TopicTagFilter(choice: .label("想法"))
        XCTAssertEqual(byLabel.highlightedIDs(in: document), [tagged, free])
        let byMarker = TopicTagFilter(choice: .marker("priority-1"))
        XCTAssertEqual(byMarker.highlightedIDs(in: document), [tagged])
        XCTAssertEqual(TopicTagIndex.labels(in: document), ["想法"])
        XCTAssertEqual(TopicTagIndex.markerIDs(in: document), ["priority-1"])
        XCTAssertTrue(TopicTagIndex.contains("想", in: "想法"))
        XCTAssertTrue(TopicTagIndex.contains("  ", in: "想法"))
        XCTAssertFalse(TopicTagIndex.contains("没有", in: "想法"))

        let imported = try FlorettaXMindCodec.importMap(try load("multi-sheet.xmind"))
        XCTAssertEqual(imported.additionalCanvases[0].roots[0].labels, ["乙"])
        XCTAssertEqual(TopicTagIndex.labels(in: imported), [])
        XCTAssertFalse(TopicTagFilter(choice: .label("乙")).highlightedIDs(in: imported).contains(imported.additionalCanvases[0].roots[0].id))
    }

    func testUndoRestoresLabelThenMarker() {
        let root = UUID()
        var document = MindMapDocument(title: "t", roots: [MindMapNode(id: root, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = root
        XCTAssertTrue(session.updateTopicTags(root, document: &document) { node in
            node.labels = TopicLabels.inserting("想法", into: node.labels)
        })
        XCTAssertTrue(session.updateTopicTags(root, document: &document) { node in
            node.markers = TopicMarkerCatalog.assign(node.markers, markerID: "task-done", group: .progress)
        })
        XCTAssertTrue(session.updateTopicTags(root, document: &document) { node in
            node.labels = ["想法"]
        })
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.node(root)?.markers, [])
        XCTAssertEqual(document.node(root)?.labels, ["想法"])
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.node(root)?.labels, [])
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.node(root)?.labels, ["想法"])
    }

    func testTaggedTopicIsTallerByTheTagBandOnly() {
        let plain = MindMapDocument(title: "t", roots: [MindMapNode(text: "甲")])
        var taggedNode = MindMapNode(text: "甲", labels: ["想法"], markers: [TopicMarker(markerId: "flag-red")])
        let tagged = MindMapDocument(title: "t", roots: [taggedNode])
        let plainHeight = LayoutEngine().layout(plain)[0].size.height
        let taggedFrame = LayoutEngine().layout(tagged)[0]
        let band = TopicTagLayout.bandHeight(labelCount: 1, markerCount: 1)
        XCTAssertEqual(taggedFrame.size.height - plainHeight, band, accuracy: 0.01)
        XCTAssertEqual(taggedFrame.tagBandHeight, band, accuracy: 0.01)
        XCTAssertEqual(taggedFrame.labels, ["想法"])
        XCTAssertEqual(taggedFrame.markerIDs, ["flag-red"])
        XCTAssertEqual(LayoutEngine().layout(plain)[0].tagBandHeight, 0, accuracy: 0.01)
        taggedNode.labels = []
        taggedNode.markers = []
        XCTAssertEqual(TopicTagLayout.bandHeight(labelCount: 0, markerCount: 0), 0)
    }

    func testXMindEditWritesLabelsAndKeepsUnknownMarkerKeys() throws {
        var imported = try FlorettaXMindCodec.importMap(try load("simple.xmind"))
        imported.roots[0].labels = ["新标签"]
        let exported = try FlorettaXMindCodec.export(imported)
        let text = try XCTUnwrap(String(data: try entry(exported, "content.json"), encoding: .utf8))
        XCTAssertTrue(text.contains("新标签"))
        XCTAssertFalse(text.contains("想法"))
        XCTAssertTrue(text.contains("priority-1"))
        let again = try FlorettaXMindCodec.importMap(exported)
        XCTAssertEqual(again.roots[0].labels, ["新标签"])
        XCTAssertEqual(again.roots[0].children[0].markers.map(\.markerId), ["priority-1"])

        let content = """
        [{"id":"sheet-1","class":"sheet","title":"图","rootTopic":{"id":"center","class":"topic","title":"中心","labels":["保持"],"markers":[{"markerId":"star-red","extra":1}]}}]
        """
        let data = workbook(content: content)
        var marked = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(marked.roots[0].labels, ["保持"])
        XCTAssertEqual(marked.roots[0].markers.map(\.markerId), ["star-red"])
        marked.roots[0].text = "新的中心"
        let rewritten = try FlorettaXMindCodec.export(marked)
        let rewrittenText = try XCTUnwrap(String(data: try entry(rewritten, "content.json"), encoding: .utf8))
        XCTAssertTrue(rewrittenText.contains("star-red"))
        XCTAssertTrue(rewrittenText.contains("\"extra\":1"))
        XCTAssertTrue(rewrittenText.contains("保持"))
        let round = try FlorettaXMindCodec.importMap(rewritten)
        XCTAssertEqual(round.roots[0].text, "新的中心")
        XCTAssertEqual(round.roots[0].labels, ["保持"])
        XCTAssertEqual(round.roots[0].markers.map(\.markerId), ["star-red"])
    }

    func testOldFlorettaFilePromotesLabelsWithoutChangingXMindBytes() throws {
        let data = try load("simple.xmind")
        var imported = try FlorettaXMindCodec.importMap(data)
        imported.roots[0].labels = []
        imported.roots[0].children[0].markers = []
        imported.xmindForeign?.snapshot.tagsMapped = false
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(imported))
        XCTAssertEqual(decoded.roots[0].labels, ["想法"])
        XCTAssertEqual(decoded.roots[0].children[0].markers.map(\.markerId), ["priority-1"])
        XCTAssertEqual(decoded.xmindForeign?.snapshot.tagsMapped, true)
        let exported = try FlorettaXMindCodec.export(decoded)
        XCTAssertEqual(try entry(exported, "content.json"), try entry(data, "content.json"))
    }

    func testNativeXMindExportWritesLabelsAndMarkers() throws {
        let child = MindMapNode(
            text: "分支",
            labels: ["想法"],
            markers: [TopicMarker(markerId: "priority-1"), TopicMarker(markerId: "task-done")]
        )
        let document = MindMapDocument(title: "图", roots: [MindMapNode(text: "中心", children: [child])])
        let exported = try FlorettaXMindCodec.export(document)
        let again = try FlorettaXMindCodec.importMap(exported)
        XCTAssertEqual(again.roots[0].children[0].labels, ["想法"])
        XCTAssertEqual(again.roots[0].children[0].markers.map(\.markerId), ["priority-1", "task-done"])
    }

    func testFilterOfThousandTopicsStaysUnderATenthOfASecond() {
        var children: [MindMapNode] = []
        children.reserveCapacity(1_000)
        for index in 0..<1_000 {
            var node = MindMapNode(text: "n\(index)")
            if index.isMultiple(of: 10) {
                node.labels = ["保持"]
                node.markers = [TopicMarker(markerId: "flag-green")]
            }
            children.append(node)
        }
        let document = MindMapDocument(title: "宽", roots: [MindMapNode(text: "根", children: children)])
        let filter = TopicTagFilter(choice: .label("保持"))
        let clock = ContinuousClock()
        let start = clock.now
        let ids = filter.highlightedIDs(in: document)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(ids.count, 100)
        XCTAssertLessThan(elapsed, .milliseconds(100), "filter of 1000 topics took \(elapsed)")
    }

    private func load(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/XMind")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func workbook(content: String) -> Data {
        ZipArchive.write([
            ZipEntry(name: "content.json", data: Data(content.utf8)),
            ZipEntry(name: "metadata.json", data: Data(#"{"dataStructureVersion":"2"}"#.utf8)),
            ZipEntry(name: "manifest.json", data: Data(#"{"file-entries":{"content.json":{},"metadata.json":{},"manifest.json":{}}}"#.utf8)),
        ])
    }

    private func entry(_ data: Data, _ name: String) throws -> Data {
        let entries = try ZipArchive.read(data, limits: .standard)
        return try XCTUnwrap(entries.first { $0.name == name }?.data)
    }
}
