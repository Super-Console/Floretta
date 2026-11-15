import FlorettaCore
import XCTest

/// The 结构 row is the only way a user reaches the layout engine. These tests keep
/// that row, its seven names, and its one write path from disappearing.
final class InspectorStructureTests: XCTestCase {
    /// XMind's English names and the Chinese names the inspector shows, in the
    /// order the picker lists them.
    private let titles: [(kind: LayoutKind, chinese: String, english: String)] = [
        (.bilateral, "思维导图", "Mind Map"),
        (.logicChart, "逻辑图", "Logic Chart"),
        (.orgChart, "组织结构图", "Org Chart"),
        (.timeline, "时间轴", "Timeline"),
        (.fishbone, "鱼骨图", "Fishbone"),
        (.treeTable, "树型表格", "Tree Table"),
        (.matrix, "矩阵图", "Matrix"),
    ]

    func testStructureSectionSitsRightAfterShape() {
        let sections = InspectorStyle.sections
        XCTAssertEqual(Array(sections.map(\.rawValue).prefix(2)), ["shape", "structure"])
        XCTAssertEqual(InspectorStyleSection.structure.titleKey, "结构")
        XCTAssertTrue(
            InspectorStyleSection.structure.isDocumentScope,
            "a structure belongs to the document, so the row stays visible with nothing selected"
        )
        XCTAssertEqual(
            sections.filter(\.isDocumentScope),
            [.structure, .branch, .colorScheme, .background, .globalFont]
        )
        XCTAssertEqual(
            sections.map(\.titleKey),
            ["形状", "结构", "填充", "边框", "宽度", "文本", "分支", "配色方案", "背景色", "全局字体", "连到"]
        )
        XCTAssertEqual(LayoutKind.allCases.count, 7, "the picker offers every structure the engine draws")
    }

    func testEveryKindHasAChineseAndAnEnglishTitle() throws {
        let catalog = try catalogStrings()
        var seen = Set<String>()
        for item in titles {
            let key = item.kind.displayNameKey
            XCTAssertTrue(key.hasPrefix("layout."), key)
            let entry = try XCTUnwrap(catalog[key] as? [String: Any], "missing catalog key \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(try value(localizations, "zh-Hans"), item.chinese, key)
            XCTAssertEqual(try value(localizations, "en"), item.english, key)
            XCTAssertNotEqual(item.english, key, "an untranslated key must never reach the picker")
            XCTAssertTrue(seen.insert(item.chinese).inserted, "two structures share a Chinese title")
            XCTAssertTrue(seen.insert(item.english).inserted, "two structures share an English title")
        }
        XCTAssertEqual(
            LayoutKind.allCases.map(\.displayNameKey),
            titles.map(\.kind.displayNameKey),
            "the picker lists LayoutKind.allCases in this order"
        )
    }

    func testChoosingAStructureWritesTheDocumentAndRelaysOut() {
        let root = MindMapNode(text: "根", children: [
            MindMapNode(text: "甲", children: [MindMapNode(text: "甲一")]),
            MindMapNode(text: "乙"),
        ])
        var document = MindMapDocument(title: "结构", roots: [root])
        var keyboard = MindMapKeyboardSession()
        let bilateral = LayoutEngine.forDocument(document).layout(document)

        XCTAssertTrue(keyboard.setLayoutKind(.fishbone, document: &document))
        XCTAssertEqual(document.layoutKind, .fishbone)
        let switched = LayoutEngine.forDocument(document).layout(document)
        XCTAssertEqual(
            switched,
            LayoutEngine(kind: .fishbone).layout(document),
            "the canvas and the exporter both build their engine from document.layoutKind"
        )
        XCTAssertNotEqual(switched, bilateral, "a switch must re-measure, not reuse the old frames")

        // One structure switch is one undo step.
        XCTAssertEqual(pressUndo(session: &keyboard, document: &document), .undo)
        XCTAssertEqual(document.layoutKind, .bilateral)
        XCTAssertEqual(LayoutEngine.forDocument(document).layout(document), bilateral)

        // Picking the structure already chosen is not a second undo step.
        XCTAssertTrue(keyboard.setLayoutKind(.timeline, document: &document))
        XCTAssertTrue(keyboard.setLayoutKind(.timeline, document: &document))
        XCTAssertEqual(document.layoutKind, .timeline)
        XCTAssertEqual(pressUndo(session: &keyboard, document: &document), .undo)
        XCTAssertEqual(document.layoutKind, .bilateral, "one undo returns to the structure before the first pick")

        var typing = MindMapKeyboardSession()
        typing.mode = .edit
        XCTAssertFalse(typing.setLayoutKind(.matrix, document: &document), "an open edit is not a structure switch")
        XCTAssertEqual(document.layoutKind, .bilateral)
    }

    /// A source guard: the row, its seven names, and its write path live in the
    /// inspector and nowhere else.
    func testInspectorKeepsOneStructureRowThatWritesThroughTheSession() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let page = try slice(editor, from: "private var stylePage", until: "/// 结构. Seven structures")
        XCTAssertTrue(page.contains("inspectorStructureSection"), "the style page renders the row")
        let row = try slice(editor, from: "/// 结构. Seven structures", until: "/// 配色方案. Writes the same")
        XCTAssertTrue(row.contains("ForEach(LayoutKind.allCases"), "every structure is offered")
        XCTAssertTrue(row.contains("text(kind.displayNameKey)"), "the row shows the localized title, never the raw key")
        XCTAssertTrue(row.contains("inspector.style.structure"))
        XCTAssertTrue(row.contains("session.setLayoutKind(kind)"))
        let session = try repoFile("Floretta/Shared/Shell/DocumentSession.swift")
        XCTAssertTrue(session.contains("func setLayoutKind(_ kind: LayoutKind)"))
        XCTAssertTrue(session.contains("keyboard.setLayoutKind(kind, document: &document)"))
    }

    private func catalogStrings() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Floretta/Shared/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: Any])
    }

    private func value(_ localizations: [String: Any], _ language: String) throws -> String {
        let entry = try XCTUnwrap(localizations[language] as? [String: Any], language)
        let unit = try XCTUnwrap(entry["stringUnit"] as? [String: Any], language)
        let text = try XCTUnwrap(unit["value"] as? String, language)
        XCTAssertFalse(text.isEmpty, language)
        return text
    }

    @discardableResult
    private func pressUndo(
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument
    ) -> MindMapCommand? {
        let frames = LayoutEngine().layout(document)
        let event = KeyEvent(
            key: .character("z"),
            modifiers: .command,
            mode: session.mode,
            isComposing: session.isComposing
        )
        return session.handle(event, document: &document, frames: frames)
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
