import XCTest

/// The macOS menu bar, pinned by source.
///
/// The bug this file exists for: the same `Commands` value was attached to two
/// scenes, so SwiftUI installed its custom menus twice — 文件 编辑 显示 插入 视图
/// 格式 导出 主题 帮助, then 插入 视图 格式 导出 主题 帮助 again, then the system
/// 窗口 and 帮助 menus. A menu bar is app-wide ("the menu bar populates with
/// menus and menu items based on the implemented scenes and commands"), so one
/// declaration is the whole requirement.
final class MacMenuBarContractTests: XCTestCase {
    func testCommandsAreDeclaredByExactlyOneScene() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        XCTAssertEqual(
            app.components(separatedBy: ".commands {").count - 1,
            1,
            "two scenes carrying the same Commands is what duplicated every custom menu"
        )
        XCTAssertEqual(
            app.components(separatedBy: "FlorettaCommands(settings: settings, library: library)").count - 1,
            1,
            "the command set is installed once"
        )
        // The same-document window is still a scene; it simply reads the focused
        // editor through FocusedValue like every other menu item does.
        XCTAssertTrue(app.contains("WindowGroup(id: SameDocumentWindow.sceneID"))
    }

    func testNoMenuTitleAppearsTwice() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let titles = commandMenuTitles(in: app)
        XCTAssertEqual(titles.count, Set(titles).count, "menu titles repeat: \(titles)")
        XCTAssertEqual(titles, ["插入", "格式", "主题"], "only the app-specific menus are top-level")
    }

    /// 导出 belongs to 文件, 视图 is the system 显示 menu, and 快捷键一览 is the
    /// system 帮助 menu. None of them is a top-level menu of its own.
    func testExportsViewsAndHelpLiveInTheSystemMenus() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")

        XCTAssertFalse(app.contains("CommandMenu(\"导出\")"), "导出 is a submenu of 文件")
        let export = try slice(app, from: "CommandGroup(after: .saveItem) {", until: "CommandGroup(after: .textEditing)")
        XCTAssertTrue(export.contains("Menu {"), "one 导出 submenu")
        XCTAssertTrue(export.contains("导出为…"))
        for id in ["png", "pdf", "markdownExport", "textBundle", "saveFloretta", "mm", "opml", "xmind"] {
            XCTAssertTrue(export.contains(".\(id)"), "the \(id) export moved into the submenu")
        }

        // 显示
        XCTAssertFalse(app.contains("CommandMenu(\"视图\")"), "视图 sat beside the system 显示 menu")
        XCTAssertTrue(app.contains("CommandGroup(after: .sidebar)"))
        let view = try slice(app, from: "private func viewCommands", until: "private func topicShortcut")
        for id in ["fit", "outline", "mapMode", "focusMode", "immersive", "style"] {
            XCTAssertTrue(view.contains(".\(id)"), "the \(id) view command joins 显示")
        }
        XCTAssertTrue(view.contains("zoomIn"), "the zoom family stays in 显示")

        // 帮助
        XCTAssertFalse(app.contains("CommandMenu(\"帮助\")"), "a second 帮助 menu sat beside the system one")
        XCTAssertTrue(app.contains("CommandGroup(replacing: .help)"))
        let help = try slice(app, from: "CommandGroup(replacing: .help)", until: "// 窗口 > 新建窗口")
        XCTAssertTrue(help.contains("快捷键一览"))
        // The chord is the one 设置 ▸ 快捷键 holds, so a rebind shows here at once.
        XCTAssertTrue(help.contains("topicButton(\"快捷键一览\", command: .showShortcutHelp)"))
    }

    /// The system menus are never re-declared: a second 文件 / 编辑 / 显示 / 窗口
    /// menu is the same bug in another shape.
    func testSystemMenusAreNotRedeclared() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        for title in ["文件", "编辑", "显示", "窗口", "帮助", "视图", "导出"] {
            XCTAssertFalse(app.contains("CommandMenu(\"\\(title)\")"), "\\(title) is not ours to declare")
        }
        // The groups this app adds to the system menus are the conventional ones.
        XCTAssertTrue(app.contains("CommandGroup(replacing: .newItem)"))
        XCTAssertTrue(app.contains("CommandGroup(after: .newItem)"))
        XCTAssertTrue(app.contains("CommandGroup(replacing: .saveItem)"))
        XCTAssertTrue(app.contains("CommandGroup(after: .textEditing)"))
        XCTAssertTrue(app.contains("CommandGroup(before: .windowList)"))
        XCTAssertTrue(app.contains("SidebarCommands()"))
    }

    func testFileMenuContainsDocumentActionsAndPreservesDisabledSave() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let session = try repoFile("Floretta/Shared/Shell/DocumentSession.swift")
        let content = try repoFile("Floretta/Shared/ContentView.swift")
        let fileCommands = try slice(app, from: "// 文件", until: "// 显示:")

        XCTAssertTrue(fileCommands.contains("最近打开"))
        XCTAssertTrue(fileCommands.contains("library.recents"))
        XCTAssertTrue(fileCommands.contains("library.openRecent(entry)"))
        XCTAssertTrue(fileCommands.contains("library.closeEditor()"))
        XCTAssertTrue(fileCommands.contains(".keyboardShortcut(\"w\", modifiers: .command)"))
        XCTAssertTrue(fileCommands.contains("复制副本"))
        XCTAssertTrue(fileCommands.contains("另存为"))
        XCTAssertTrue(fileCommands.contains(".keyboardShortcut(\"s\", modifiers: [.command, .shift])"))
        XCTAssertTrue(fileCommands.contains("导入"))
        XCTAssertTrue(fileCommands.contains(".importFile"))
        XCTAssertTrue(fileCommands.contains(".printMap"))
        XCTAssertTrue(fileCommands.contains("共享"))

        let save = try slice(app, from: "CommandGroup(replacing: .saveItem)", until: "// 显示:")
        XCTAssertTrue(save.contains("library.saveActiveFile()"))
        XCTAssertTrue(save.contains(".disabled(!library.canSaveActiveFile)"))
        XCTAssertTrue(save.contains(".keyboardShortcut(\"s\", modifiers: .command)"))
        XCTAssertFalse(save.hasPrefix("if let editorCommands"), "save stays present when no editor focus value exists")

        let actions = try slice(editor, from: "private var editorMenuActions", until: "private var toolbarWidthClass")
        XCTAssertTrue(actions.contains(".importFile"), "the File import item must call the existing importer")
        XCTAssertTrue(actions.contains(".printMap"), "the File print item must call the existing print operation")
        XCTAssertTrue(actions.contains("duplicateDocument"))
        XCTAssertTrue(actions.contains("saveAsDocument"))

        let exportCompletion = try slice(editor, from: "private func finishFlorettaExport", until: "private func exportFlorettaCopy")
        XCTAssertTrue(exportCompletion.contains("case .duplicate:") && exportCompletion.contains("onDuplicatedCopy(url)"))
        XCTAssertTrue(exportCompletion.contains("case .saveAs:") && exportCompletion.contains("onSavedAs(url)"))
        XCTAssertTrue(content.contains("onDuplicatedCopy: { library.noteDuplicatedCopy($0) }"))
        XCTAssertTrue(content.contains("onSavedAs: { library.noteSavedAsCopy($0) }"))

        let duplicate = try slice(session, from: "func noteDuplicatedCopy", until: "func noteSavedAsCopy")
        XCTAssertFalse(duplicate.contains("editor.url = url"), "a duplicate does not redirect the current document")
        let saveAs = try slice(session, from: "func noteSavedAsCopy", until: "/// ⌘S.")
        XCTAssertTrue(saveAs.contains("editor.url = url"), "Save As adopts its new document URL")
        XCTAssertTrue(saveAs.contains("editor.sourceExtension = \"floretta\""))
    }

    func testFileMenuDoesNotClaimUnsupportedSVGExport() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let fileCommands = try slice(app, from: "// 文件", until: "// 显示:")
        XCTAssertFalse(fileCommands.localizedCaseInsensitiveContains("svg"), "do not advertise an exporter that does not exist")
    }

    private func commandMenuTitles(in source: String) -> [String] {
        var titles: [String] = []
        var rest = Substring(source)
        while let start = rest.range(of: "CommandMenu(\"") {
            let afterQuote = rest[start.upperBound...]
            guard let end = afterQuote.firstIndex(of: "\"") else { break }
            titles.append(String(afterQuote[..<end]))
            rest = afterQuote[end...]
        }
        return titles
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
