import XCTest

final class MacMenuExpansionContractTests: XCTestCase {
    func testHelpMenuHasARealGuideAndFeedbackRoute() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let help = try slice(app, from: "CommandGroup(replacing: .help)", until: "// 窗口 > 新建窗口")

        XCTAssertTrue(help.contains("使用手册"))
        XCTAssertTrue(help.contains("反馈问题"))
        XCTAssertTrue(help.contains("showUserGuide"))
        XCTAssertTrue(help.contains("openFeedback"))
        XCTAssertTrue(editor.contains("settings.shortcutBindings.entries()"), "the shortcut guide must list the current bindings, including bare topic keys")
    }

    func testEditMenuSearchReplaceSelectionAndDeleteAreActionBound() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let session = try repoFile("Floretta/Shared/Shell/DocumentSession.swift")
        let edit = try slice(app, from: "CommandGroup(after: .textEditing)", until: "// 显示:")

        XCTAssertTrue(edit.contains("查找下一个"))
        XCTAssertTrue(edit.contains("替换"))
        XCTAssertTrue(edit.contains("全选"))
        XCTAssertTrue(edit.contains("editorCommands.findNext?()"))
        XCTAssertTrue(edit.contains("editorCommands.showReplace?()"))
        XCTAssertTrue(edit.contains("editorCommands.selectAll?()"))
        XCTAssertTrue(edit.contains("editorCommands.perform[.delete]?()"))
        XCTAssertTrue(edit.contains(".keyboardShortcut(\"g\", modifiers: .command)"))
        XCTAssertTrue(edit.contains(".keyboardShortcut(\"f\", modifiers: [.command, .option])"))
        XCTAssertTrue(editor.contains("CanvasEditCommands.findNext"))
        XCTAssertTrue(session.contains("static func replaceTopicText"), "replace must mutate topic text, not labels or notes")
    }

    func testViewMenuExposesZoomFullscreenInspectorAndSidebar() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let view = try slice(app, from: "private func viewCommands", until: "private func topicShortcut")

        XCTAssertTrue(app.contains("SidebarCommands()"), "use the system sidebar command")
        XCTAssertTrue(view.contains("全屏"))
        XCTAssertTrue(view.contains("toggleFullScreen"))
        XCTAssertTrue(view.contains("显示或隐藏检查器"))
        XCTAssertTrue(view.contains("EditorToolbarCommandID.style"))
        XCTAssertTrue(view.contains(".keyboardShortcut(\"i\", modifiers: [.command, .option])"))
        XCTAssertTrue(view.contains("放大"))
        XCTAssertTrue(view.contains("缩小"))
        XCTAssertTrue(view.contains("实际大小"))
        XCTAssertTrue(view.contains(".keyboardShortcut(\"0\", modifiers: .command)"), "⌘0 is reserved for actual size")
    }

    func testInsertMenuOnlyListsActionsWithRealHandlers() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let catalog = try repoFile("FlorettaCore/Editor/EditorToolbarCatalog.swift")
        let insert = try slice(app, from: "CommandMenu(\"插入\")", until: "CommandMenu(\"格式\")")

        for title in ["关系线", "标记与标签", "备注"] {
            XCTAssertTrue(insert.contains(title), "missing Insert action: \(title)")
        }
        for id in [".child", ".sibling", ".freeNode", ".image"] {
            XCTAssertTrue(insert.contains(id), "missing Insert command: \(id)")
        }
        XCTAssertTrue(insert.contains(".tagFilter"))
        XCTAssertTrue(insert.contains("showNodeNote?()"))
        XCTAssertTrue(catalog.contains("item(.image, \"图片\""), "the image command's displayed title comes from the toolbar catalog")
        XCTAssertTrue(editor.contains("showNodeNote"))
        XCTAssertFalse(insert.contains("标记与图标"), "do not claim a generic icon picker that the app does not have")
    }

    func testFormatMenuActionsWriteAlignmentShapeBranchAndBorder() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let format = try slice(app, from: "CommandMenu(\"格式\")", until: "CommandMenu(\"主题\")")

        for title in ["文字对齐", "节点形状", "连线样式", "边框"] {
            XCTAssertTrue(format.contains(title), "missing Format action: \(title)")
        }
        XCTAssertTrue(format.contains("textAlignmentTitle(alignment)"))
        XCTAssertTrue(app.contains("case .leading: \"靠左\""))
        XCTAssertTrue(app.contains("case .center: \"居中\""))
        XCTAssertTrue(app.contains("case .trailing: \"靠右\""))
        XCTAssertTrue(format.contains("setTextAlignment"))
        XCTAssertTrue(format.contains("setNodeShape"))
        XCTAssertTrue(format.contains("setBranchLine"))
        XCTAssertTrue(format.contains("setBorderStyle"))
        XCTAssertTrue(editor.contains("MindMapTextAlignment"))
        XCTAssertTrue(editor.contains("InspectorStyle.applyDocument"))
    }

    func testEditMenuProvidesOutlineAndDepthFoldingActions() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let session = try repoFile("Floretta/Shared/Shell/DocumentSession.swift")
        let edit = try slice(app, from: "CommandGroup(after: .textEditing)", until: "// 显示:")

        XCTAssertTrue(edit.contains("大纲 ⇄ 导图"))
        XCTAssertTrue(edit.contains("展开全部"))
        XCTAssertTrue(edit.contains("收起全部"))
        XCTAssertTrue(edit.contains("折叠到第"))
        XCTAssertTrue(edit.contains("collapseToLevel?(level)"))
        XCTAssertTrue(editor.contains("CanvasEditCommands.collapse(toLevel:"))
        XCTAssertTrue(session.contains("static func collapse(toLevel level:"))
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
