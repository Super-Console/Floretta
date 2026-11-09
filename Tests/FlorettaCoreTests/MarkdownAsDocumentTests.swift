import FlorettaCore
import Foundation
import XCTest

final class MarkdownAsDocumentTests: XCTestCase {
    func testSimpleListRoundTripKeepsOrderForPathIndexes() throws {
        let opened = try openFixture("simple-list.md")
        XCTAssertTrue(opened.warnings.isEmpty)
        let roots = opened.document.roots
        XCTAssertEqual(roots.map(\.text), ["根级节点 A", "根级节点 B"])
        XCTAssertFalse(roots[0].isMarkdownSectionHeading)
        // root/0/0/0 and root/1 — sibling indexes are file order.
        XCTAssertEqual(roots[0].children[0].text, "子节点")
        XCTAssertEqual(roots[0].children[0].children[0].text, "孙节点")
        XCTAssertEqual(roots[1].children.map(\.text), ["子节点 B1"])
        assertDefaults(roots[0])
        try assertRoundTrip("simple-list.md")
    }

    func testSectionsAreH1RootsAndChildrenStayLists() throws {
        let opened = try openFixture("with-sections.md")
        XCTAssertEqual(opened.document.roots.map(\.text), ["分区一", "分区二"])
        XCTAssertTrue(opened.document.roots.allSatisfy(\.isMarkdownSectionHeading))
        XCTAssertEqual(opened.document.roots[0].children.map(\.text), ["A", "B"])
        XCTAssertEqual(opened.document.roots[0].children[0].children.map(\.text), ["A1"])
        XCTAssertFalse(opened.document.roots[0].children[0].isMarkdownSectionHeading)
        XCTAssertEqual(opened.document.roots[1].children[0].children[0].children[0].text, "C2")
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertTrue(saved.contains("# 分区一\n"))
        XCTAssertTrue(saved.contains("# 分区二\n"))
        XCTAssertFalse(saved.contains("##"))
        try assertRoundTrip("with-sections.md")
    }

    func testRejectH2NamesTheLineAndDoesNotOpen() throws {
        let text = try fixture("reject-h2.md")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let index = try XCTUnwrap(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("##") })
        let lineNumber = index + 1
        XCTAssertThrowsError(try FlorettaMarkdownDocumentCodec.open(text)) { error in
            guard case .illegalHeading(let line, let level) = error as? FlorettaMarkdownDocumentError else {
                return XCTFail("expected illegal heading, got \(error)")
            }
            XCTAssertEqual(line, lineNumber)
            XCTAssertEqual(level, 2)
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("第 \(lineNumber) 行"), message)
        }
    }

    func testNotesAndSingleLinksRoundTrip() throws {
        let opened = try openFixture("with-notes-links.md")
        let parent = opened.document.roots[0]
        XCTAssertEqual(parent.text, "父节点")
        XCTAssertEqual(parent.note, "父备注第一行\n父备注第二行")
        XCTAssertNil(parent.link)
        XCTAssertEqual(parent.children[0].text, "子节点")
        XCTAssertEqual(parent.children[0].link, "https://example.com/a")
        XCTAssertEqual(parent.children[0].note, "子备注")
        XCTAssertEqual(parent.children[1].text, "参见 [甲](https://a.example) 和 [乙](https://b.example)")
        XCTAssertNil(parent.children[1].link)
        let only = opened.document.roots[1]
        XCTAssertEqual(only.text, "仅链接")
        XCTAssertEqual(only.link, "https://example.com/only")
        try assertRoundTrip("with-notes-links.md")
    }

    func testFrontMatterIsOpaqueAndPreservesKeyOrder() throws {
        let text = try fixture("with-front-matter.md")
        let opened = try FlorettaMarkdownDocumentCodec.open(text)
        let expected = """
        ---
        title: 保持键序
        tags:
          - one
          - two
        note: "不要解析进节点"
        ---
        """
        XCTAssertEqual(opened.document.markdownFrontMatter, expected)
        XCTAssertEqual(opened.document.roots.map(\.text), ["正文"])
        XCTAssertEqual(opened.document.roots[0].children.map(\.text), ["子层"])
        XCTAssertFalse(opened.document.roots[0].text.contains("保持键序"))
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertTrue(saved.hasPrefix(expected + "\n\n"))
        try assertRoundTrip("with-front-matter.md")
    }

    func testMarkersAndTabsNormalizeOnceAndWriteCanonicalLists() throws {
        let text = try fixture("markers-and-tabs.md")
        XCTAssertTrue(text.contains("\t"))
        let opened = try FlorettaMarkdownDocumentCodec.open(text)
        XCTAssertEqual(
            opened.warnings,
            [.normalizedListMarker, .normalizedTabIndent]
        )
        XCTAssertFalse(opened.warnings[0].message.isEmpty)
        XCTAssertFalse(opened.warnings[1].message.isEmpty)
        let roots = opened.document.roots
        XCTAssertEqual(roots.map(\.text), ["星号", "有序甲", "加号根"])
        XCTAssertEqual(roots[0].children.map(\.text), ["加号子节点"])
        XCTAssertEqual(roots[1].children.map(\.text), ["有序子"])
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertFalse(saved.contains("\t"))
        XCTAssertFalse(saved.contains("\n* "))
        XCTAssertFalse(saved.contains("+ "))
        XCTAssertFalse(saved.contains("1. "))
        XCTAssertFalse(saved.contains("2. "))
        let again = try FlorettaMarkdownDocumentCodec.open(saved)
        XCTAssertTrue(again.warnings.isEmpty)
        XCTAssertEqual(shape(again.document), shape(opened.document))
        try assertRoundTrip("markers-and-tabs.md")
    }

    func testEmptyItemsAreKeptAndDeepIndentRoundTrips() throws {
        let opened = try openFixture("empty-and-deep.md")
        let first = opened.document.roots[0]
        XCTAssertEqual(first.text, "")
        XCTAssertEqual(first.children[0].text, "第二层")
        XCTAssertEqual(first.children[0].children[0].text, "")
        XCTAssertEqual(first.children[0].children[0].children[0].text, "第四层")
        XCTAssertEqual(first.children[0].children[0].children[0].children[0].text, "第五层")
        XCTAssertEqual(opened.document.roots[1].text, "兄弟")
        XCTAssertEqual(opened.document.roots[1].children[0].text, "")
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertTrue(saved.contains("- \n"))
        try assertRoundTrip("empty-and-deep.md")
    }

    func testNoiseCommentsAreDroppedAndNotWrittenBack() throws {
        let opened = try openFixture("roundtrip-noise.md")
        XCTAssertEqual(opened.document.roots.map(\.text), ["可见", "之后"])
        XCTAssertEqual(opened.document.roots[0].children.map(\.text), ["子节点"])
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertFalse(saved.contains("<!--"))
        XCTAssertFalse(saved.contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertFalse(saved.contains("#C45C26"))
        XCTAssertFalse(saved.contains("assets/secret.png"))
        XCTAssertFalse(saved.contains("arrowlink"))
        XCTAssertFalse(saved.contains("relationship"))
        XCTAssertFalse(saved.contains("##"))
        try assertCanonicalBody(saved)
        try assertRoundTrip("roundtrip-noise.md")
    }

    func testSaveDropsUUIDColorPositionSideAndDoesNotInventRelationshipOrAttachment() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let node = MindMapNode(
            id: id,
            text: "主题",
            note: "备注",
            isCollapsed: true,
            style: MindMapNodeStyle(colorHex: "#C45C26"),
            position: MindMapPoint(x: 12345.75, y: 67890.25),
            link: "https://example.com/item",
            side: .left,
            children: [MindMapNode(text: "子")]
        )
        let saved = FlorettaMarkdownDocumentCodec.save(MindMapDocument(title: "工程", roots: [node]))
        XCTAssertFalse(saved.contains(id.uuidString))
        XCTAssertFalse(saved.contains("#C45C26"))
        XCTAssertFalse(saved.contains("12345.75"))
        XCTAssertFalse(saved.contains("67890.25"))
        XCTAssertFalse(saved.contains("left"))
        XCTAssertFalse(saved.contains("assets/"))
        XCTAssertFalse(saved.contains("relationship"))
        XCTAssertFalse(saved.contains("arrowlink"))
        XCTAssertFalse(saved.contains("<!--"))
        XCTAssertFalse(saved.contains("##"))
        XCTAssertFalse(saved.contains("collapsed"))
        XCTAssertTrue(saved.contains("- [主题](https://example.com/item)\n"))
        XCTAssertTrue(saved.contains("> 备注\n"))
        XCTAssertTrue(saved.contains("  - 子\n"))
    }

    func testTitleExportPresetStaysSeparateFromDocumentSave() throws {
        let document = MindMapDocument(
            title: "预设",
            roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])]
        )
        let preset = FlorettaMarkdown.export(document)
        XCTAssertTrue(preset.contains("# 根\n"))
        XCTAssertTrue(preset.contains("## 子\n"))
        let saved = FlorettaMarkdownDocumentCodec.save(document)
        XCTAssertTrue(saved.contains("- 根\n"))
        XCTAssertTrue(saved.contains("  - 子\n"))
        XCTAssertFalse(saved.contains("##"))
        let opened = try FlorettaMarkdownDocumentCodec.open(saved)
        XCTAssertEqual(opened.document.roots[0].text, "根")
        XCTAssertEqual(opened.document.roots[0].children[0].text, "子")
        XCTAssertThrowsError(try FlorettaMarkdownDocumentCodec.open(preset))
    }

    func testListBeforeSectionStaysASiblingRoot() throws {
        let opened = try FlorettaMarkdownDocumentCodec.open("- 前\n# 区\n- 后\n")
        XCTAssertEqual(opened.document.roots.map(\.text), ["前", "区"])
        XCTAssertFalse(opened.document.roots[0].isMarkdownSectionHeading)
        XCTAssertTrue(opened.document.roots[1].isMarkdownSectionHeading)
        XCTAssertEqual(opened.document.roots[1].children.map(\.text), ["后"])
    }

    func testSectionNoteAndLinkEscapeRoundTrip() throws {
        let section = MindMapNode(
            text: "a[b]",
            note: "分区备注\n第二行",
            link: "https://example.com/a b)",
            children: [MindMapNode(text: "子")],
            isMarkdownSectionHeading: true
        )
        let document = MindMapDocument(title: "t", roots: [section])
        let saved = FlorettaMarkdownDocumentCodec.save(document)
        XCTAssertTrue(saved.hasPrefix("# [a\\[b\\]](https://example.com/a%20b%29)\n"))
        XCTAssertTrue(saved.contains("> 分区备注\n> 第二行\n"))
        let opened = try FlorettaMarkdownDocumentCodec.open(saved)
        XCTAssertEqual(opened.document.roots[0].text, "a[b]")
        XCTAssertEqual(opened.document.roots[0].link, "https://example.com/a b)")
        XCTAssertEqual(opened.document.roots[0].note, "分区备注\n第二行")
        XCTAssertTrue(opened.document.roots[0].isMarkdownSectionHeading)
        XCTAssertEqual(opened.document.roots[0].children.map(\.text), ["子"])
        XCTAssertEqual(FlorettaMarkdownDocumentCodec.save(opened.document), saved)
    }

    func testHashesInsideListTextAreNotSections() throws {
        let opened = try FlorettaMarkdownDocumentCodec.open("- 标题写法 ## 不是分区\n")
        XCTAssertEqual(opened.document.roots[0].text, "标题写法 ## 不是分区")
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        XCTAssertTrue(saved.hasPrefix("- 标题写法 ## 不是分区\n"))
        XCTAssertFalse(saved.hasPrefix("##"))
    }

    func testProseIndentAndBareMarkerFailWithLineNumbers() {
        assertFailure("这是一段正文\n- 节点\n", line: 1) { error in
            guard case .unrecognizedLine(let line, _) = error else { return nil }
            return line
        }
        assertFailure("- 父\n    - 孙\n", line: 2) { error in
            guard case .indentJump(let line) = error else { return nil }
            return line
        }
        assertFailure("- 父\n   - 子\n", line: 2) { error in
            guard case .oddIndent(let line) = error else { return nil }
            return line
        }
        assertFailure("-\n", line: 1) { error in
            guard case .unrecognizedLine(let line, _) = error else { return nil }
            return line
        }
        assertFailure("> 没有节点\n", line: 1) { error in
            guard case .orphanBlockquote(let line) = error else { return nil }
            return line
        }
        assertFailure("---\ntitle: x\n- 节点\n", line: 1) { error in
            guard case .unclosedFrontMatter(let line) = error else { return nil }
            return line
        }
        assertFailure("<!--\n- 被注释吞掉\n", line: 1) { error in
            guard case .unclosedHTMLComment(let line) = error else { return nil }
            return line
        }
    }

    func testCRLFAndBOMOpen() throws {
        let text = "\u{feff}---\r\ntitle: x\r\n---\r\n\r\n- 甲\r\n> 备注\r\n"
        let opened = try FlorettaMarkdownDocumentCodec.open(Data(text.utf8))
        XCTAssertEqual(opened.document.markdownFrontMatter, "---\ntitle: x\n---")
        XCTAssertEqual(opened.document.roots[0].text, "甲")
        XCTAssertEqual(opened.document.roots[0].note, "备注")
    }

    func testNotUTF8Fails() {
        XCTAssertThrowsError(try FlorettaMarkdownDocumentCodec.open(Data([0xFF, 0xFE, 0xFD]))) { error in
            XCTAssertEqual(error as? FlorettaMarkdownDocumentError, .notUTF8)
        }
    }

    func testDepthPastLimitNamesTheLine() {
        var lines: [String] = []
        for level in 0...513 {
            lines.append(String(repeating: " ", count: level * 2) + "- n")
        }
        assertFailure(lines.joined(separator: "\n"), line: 514) { error in
            guard case .tooDeep(let line) = error else { return nil }
            return line
        }
    }

    func testOpenThousandNodesWithinOpenBudget() throws {
        var lines: [String] = []
        lines.reserveCapacity(1_100)
        for index in 0..<1_000 {
            lines.append("- 节点 \(index)")
            if index % 10 == 0 {
                lines.append("  - 子 \(index)")
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        _ = try FlorettaMarkdownDocumentCodec.open("- 预热\n")
        let clock = ContinuousClock()
        let start = clock.now
        let opened = try FlorettaMarkdownDocumentCodec.open(text)
        let elapsed = start.duration(to: clock.now)
        XCTAssertGreaterThanOrEqual(nodeCount(opened.document.roots), 1_000)
        XCTAssertEqual(opened.document.roots.count, 1_000)
        // docs/PERF-BUDGET.md is not in the tree; MD-AS-DOCUMENT §8.2 budgets open at <1.5s.
        XCTAssertLessThan(elapsed, .milliseconds(1500), "open of \(nodeCount(opened.document.roots)) nodes took \(elapsed)")
    }

    func testMarkdownFieldsRoundTripThroughFlorettaJSONWhenSet() throws {
        let stamped = Date(timeIntervalSince1970: 1_762_646_400)
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let document = MindMapDocument(
            title: "区",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [
                MindMapNode(
                    id: id,
                    text: "分区",
                    note: "",
                    isMarkdownSectionHeading: true
                ),
            ],
            markdownFrontMatter: "---\nkeep: yes\n---"
        )
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.markdownFrontMatter, "---\nkeep: yes\n---")
        XCTAssertTrue(decoded.roots[0].isMarkdownSectionHeading)

        let plain = MindMapDocument(
            title: "plain",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: id, text: "叶子", note: "n")]
        )
        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(plain), encoding: .utf8))
        XCTAssertFalse(json.contains("markdownFrontMatter"))
        XCTAssertFalse(json.contains("isMarkdownSectionHeading"))
    }

    private func assertRoundTrip(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let opened = try openFixture(name)
        let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
        try assertCanonicalBody(saved, file: file, line: line)
        let again = try FlorettaMarkdownDocumentCodec.open(Data(saved.utf8))
        XCTAssertEqual(shape(again.document), shape(opened.document), file: file, line: line)
        XCTAssertEqual(again.document.markdownFrontMatter, opened.document.markdownFrontMatter, file: file, line: line)
        XCTAssertTrue(again.warnings.isEmpty, file: file, line: line)
        XCTAssertNotEqual(again.document.roots.first?.id, opened.document.roots.first?.id, file: file, line: line)
        let savedAgain = FlorettaMarkdownDocumentCodec.save(again.document)
        XCTAssertEqual(savedAgain, saved, file: file, line: line)
        for node in flatten(again.document.roots) {
            assertDefaults(node, file: file, line: line)
        }
    }

    private func assertCanonicalBody(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var body = markdown
        if let frontMatterEnd = endOfFrontMatter(markdown) {
            body = String(markdown[frontMatterEnd...])
        }
        XCTAssertFalse(body.contains("\t"), file: file, line: line)
        XCTAssertFalse(body.contains("<!--"), file: file, line: line)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for entry in lines {
            if entry.isEmpty { continue }
            if entry.hasPrefix("> ") || entry == ">" { continue }
            if entry.hasPrefix("# ") { 
                XCTAssertFalse(entry.hasPrefix("##"), "illegal heading \(entry)", file: file, line: line)
                continue
            }
            var spaces = 0
            var index = entry.startIndex
            while index < entry.endIndex, entry[index] == " " {
                spaces += 1
                index = entry.index(after: index)
            }
            XCTAssertEqual(spaces % 2, 0, entry, file: file, line: line)
            let rest = String(entry[index...])
            XCTAssertTrue(rest.hasPrefix("- "), "line is not a list: \(entry)", file: file, line: line)
        }
    }

    private func endOfFrontMatter(_ markdown: String) -> String.Index? {
        guard markdown.hasPrefix("---\n") else { return nil }
        let rest = markdown.index(markdown.startIndex, offsetBy: 4)
        guard let close = markdown.range(of: "\n---\n", range: rest..<markdown.endIndex) else { return nil }
        return close.upperBound
    }

    private func assertDefaults(
        _ node: MindMapNode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(node.isCollapsed, file: file, line: line)
        XCTAssertNil(node.style, file: file, line: line)
        XCTAssertNil(node.position, file: file, line: line)
        XCTAssertNil(node.side, file: file, line: line)
    }

    private struct Shape: Equatable {
        var text: String
        var note: String
        var link: String?
        var isSection: Bool
        var children: [Shape]
    }

    private func shape(_ document: MindMapDocument) -> [Shape] {
        document.roots.map(shape)
    }

    private func shape(_ node: MindMapNode) -> Shape {
        Shape(
            text: node.text,
            note: node.note,
            link: node.link,
            isSection: node.isMarkdownSectionHeading,
            children: node.children.map(shape)
        )
    }

    private func flatten(_ nodes: [MindMapNode]) -> [MindMapNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    private func nodeCount(_ nodes: [MindMapNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + nodeCount($1.children) }
    }

    private func openFixture(_ name: String) throws -> FlorettaMarkdownOpenResult {
        try FlorettaMarkdownDocumentCodec.open(try fixture(name))
    }

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MarkdownAsDocument")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertFailure(
        _ text: String,
        line expectedLine: Int,
        match: (FlorettaMarkdownDocumentError) -> Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try FlorettaMarkdownDocumentCodec.open(text), file: file, line: line) { error in
            guard let codec = error as? FlorettaMarkdownDocumentError, let got = match(codec) else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(got, expectedLine, file: file, line: line)
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("第 \(expectedLine) 行"), message, file: file, line: line)
        }
    }
}
