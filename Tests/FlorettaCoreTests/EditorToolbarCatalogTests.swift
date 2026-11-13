import FlorettaCore
import XCTest

final class EditorToolbarCatalogTests: XCTestCase {
    func testEveryCommandHasOneSymbolAndOneTitle() {
        XCTAssertEqual(Set(EditorToolbarCatalog.commands.map(\.id)), Set(EditorToolbarCommandID.allCases))
        XCTAssertEqual(EditorToolbarCatalog.commands.count, EditorToolbarCommandID.allCases.count)
        for command in EditorToolbarCatalog.commands {
            XCTAssertFalse(command.symbol.isEmpty, command.id.rawValue)
            XCTAssertFalse(command.title.isEmpty, command.id.rawValue)
            XCTAssertEqual(EditorToolbarCatalog.command(command.id).symbol, command.symbol)
        }
    }

    func testToolbarIsIconOnlyAndMenusCarrySymbolAndTitle() {
        XCTAssertEqual(EditorToolbarCatalog.display(on: .toolbar), .iconOnly)
        XCTAssertEqual(EditorToolbarCatalog.display(on: .expandedMenu), .iconAndTitle)
        let context = EditorToolbarContext(hasSelectedTopic: true, canEncloseSelection: true)
        for command in EditorToolbarCatalog.commands {
            let bar = EditorToolbarCatalog.presentation(command.id, on: .toolbar, in: context)
            let menu = EditorToolbarCatalog.presentation(command.id, on: .expandedMenu, in: context)
            XCTAssertTrue(menu.showsSymbol, command.id.rawValue)
            XCTAssertTrue(menu.showsTitle, command.id.rawValue)
            XCTAssertEqual(menu.symbol, command.symbol)
            XCTAssertEqual(menu.title, command.title)
            XCTAssertTrue(menu.isListed)
            if command.toolbarFace == .zoomPercent {
                XCTAssertTrue(bar.showsZoomPercent, command.id.rawValue)
                XCTAssertFalse(bar.showsSymbol, command.id.rawValue)
                XCTAssertFalse(bar.showsTitle, command.id.rawValue)
            } else {
                XCTAssertTrue(bar.showsSymbol, command.id.rawValue)
                XCTAssertFalse(bar.showsTitle, command.id.rawValue)
                XCTAssertFalse(bar.showsZoomPercent, command.id.rawValue)
            }
        }
        XCTAssertEqual(EditorToolbarCatalog.command(.zoom).toolbarFace, .zoomPercent)
    }

    func testSummaryAndBoundaryStayDisabledWithoutASelection() throws {
        let root = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let child = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let document = MindMapDocument(
            title: "圈",
            roots: [MindMapNode(id: root, text: "根", children: [MindMapNode(id: child, text: "子")])]
        )
        let insert = EditorToolbarCatalog.menu(.insert)
        XCTAssertTrue(insert.contains(.summary))
        XCTAssertTrue(insert.contains(.boundary))
        XCTAssertTrue(insert.contains(.region))
        XCTAssertLessThan(try XCTUnwrap(insert.firstIndex(of: .summary)), try XCTUnwrap(insert.firstIndex(of: .boundary)))
        XCTAssertLessThan(try XCTUnwrap(insert.firstIndex(of: .boundary)), try XCTUnwrap(insert.firstIndex(of: .region)))

        var nothing = EditorToolbarContext()
        nothing.canEncloseSelection = document.canEnclose(nil)
        assertSummaryAndBoundary(enabled: false, in: nothing)

        var rootSelected = EditorToolbarContext(hasSelectedTopic: true)
        rootSelected.canEncloseSelection = document.canEnclose(root)
        XCTAssertFalse(rootSelected.canEncloseSelection)
        assertSummaryAndBoundary(enabled: false, in: rootSelected)

        var childSelected = EditorToolbarContext(hasSelectedTopic: true)
        childSelected.canEncloseSelection = document.canEnclose(child)
        XCTAssertTrue(childSelected.canEncloseSelection)
        assertSummaryAndBoundary(enabled: true, in: childSelected)

        childSelected.isMarkdownDocument = true
        assertSummaryAndBoundary(enabled: false, in: childSelected)

        let listed = EditorToolbarCatalog.presentation(.summary, on: .expandedMenu, in: nothing)
        XCTAssertFalse(listed.isEnabled)
        XCTAssertTrue(listed.isListed)
        XCTAssertEqual(listed.symbol, "curlybraces")
        XCTAssertEqual(listed.title, "概要")
        XCTAssertTrue(listed.showsSymbol)
        XCTAssertTrue(listed.showsTitle)
        let boundary = EditorToolbarCatalog.presentation(.boundary, on: .expandedMenu, in: nothing)
        XCTAssertEqual(boundary.symbol, "rectangle.dashed")
        XCTAssertEqual(boundary.title, "边界")
        XCTAssertTrue(boundary.isListed)
        XCTAssertFalse(boundary.isEnabled)
    }

    func testLinkAndHistoryFollowSelectionAndTheSavedPackage() {
        var context = EditorToolbarContext()
        XCTAssertFalse(EditorToolbarCatalog.isEnabled(.link, in: context))
        XCTAssertTrue(EditorToolbarCatalog.menu(.insert).contains(.link))
        XCTAssertEqual(EditorToolbarCatalog.command(.link).kind, .submenu)
        XCTAssertEqual(EditorToolbarCatalog.command(.viewMode).kind, .submenu)

        context.hasSelectedTopic = true
        XCTAssertTrue(EditorToolbarCatalog.isEnabled(.link, in: context))
        context.isMarkdownDocument = true
        XCTAssertFalse(EditorToolbarCatalog.isEnabled(.link, in: context))

        context = EditorToolbarContext()
        XCTAssertFalse(EditorToolbarCatalog.isEnabled(.history, in: context))
        XCTAssertTrue(EditorToolbarCatalog.menu(.more).contains(.history))
        context.canOpenSnapshotHistory = true
        XCTAssertTrue(EditorToolbarCatalog.isEnabled(.history, in: context))

        XCTAssertFalse(EditorToolbarCatalog.isEnabled(.dictation, in: EditorToolbarContext(isComposing: true)))
        XCTAssertTrue(EditorToolbarCatalog.isEnabled(.dictation, in: EditorToolbarContext()))
        XCTAssertFalse(EditorToolbarCatalog.isEnabled(.freeNode, in: EditorToolbarContext(isMarkdownDocument: true)))
    }

    func testDefaultToolbarMatchesTheCurrentBarAndTheRestCanBeAdded() {
        XCTAssertEqual(
            EditorToolbarCatalog.defaultToolbarItems,
            [.undo, .redo, .delete, .insert, .share, .zoom, .immersive, .more]
        )
        XCTAssertTrue(EditorToolbarCatalog.addableToolbarItems.contains(.summary))
        XCTAssertTrue(EditorToolbarCatalog.addableToolbarItems.contains(.boundary))
        XCTAssertTrue(EditorToolbarCatalog.addableToolbarItems.contains(.region))
        XCTAssertFalse(EditorToolbarCatalog.menu(.more).contains(.viewMode))
        XCTAssertFalse(EditorToolbarCatalog.menu(.more).contains(.newCanvas))
        for id in [EditorToolbarCommandID.viewMode, .mapMode, .focusMode, .newCanvas] {
            XCTAssertEqual(EditorToolbarCatalog.command(id).customization, .menuOnly, id.rawValue)
        }
        XCTAssertFalse(EditorToolbarCatalog.defaultToolbarItems.contains(.summary))
        for id in EditorToolbarCatalog.addableToolbarItems {
            XCTAssertEqual(EditorToolbarCatalog.command(id).customization, .addable)
        }
        for id in EditorToolbarCatalog.menu(.share) {
            XCTAssertEqual(EditorToolbarCatalog.command(id).customization, .menuOnly, id.rawValue)
        }
        XCTAssertEqual(EditorToolbarCatalog.command(.undo).placement, .principal)
        XCTAssertEqual(EditorToolbarCatalog.command(.insert).placement, .primary)
        XCTAssertFalse(EditorToolbarCatalog.menu(.more).contains(.about))
        XCTAssertEqual(EditorToolbarCatalog.command(.about).customization, .menuOnly)
        XCTAssertEqual(EditorToolbarCatalog.command(.more).symbol, "ellipsis")
        XCTAssertFalse(EditorToolbarCatalog.command(.more).help.contains("关于"))
    }

    func testEditorUsesTheCatalogForBothSurfacesAndTheSystemToolbar() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let chrome = try repoFile("Floretta/Shared/Shell/EditorToolbarChrome.swift")
        XCTAssertTrue(chrome.contains("Text(verbatim: title)"))
        XCTAssertTrue(chrome.contains("Image(systemName: symbol)"))
        XCTAssertTrue(chrome.contains(".labelStyle(.iconOnly)"))
        XCTAssertTrue(chrome.contains(".labelStyle(.titleAndIcon)"))
        XCTAssertTrue(editor.contains("EditorToolbarCatalog.display(on: surface)"))
        XCTAssertTrue(editor.contains("surface: .toolbar"))
        XCTAssertTrue(editor.contains("surface: .expandedMenu"))
        XCTAssertTrue(editor.contains("EditorToolbarCatalog.isEnabled"))
        XCTAssertTrue(editor.contains(".toolbar(id: \"floretta.editor\")"))
        XCTAssertTrue(editor.contains("toolbar.displayMode = .iconOnly"))
        XCTAssertTrue(editor.contains(".defaultCustomization("))
        XCTAssertTrue(editor.contains("ToolbarItem(id:"))
        XCTAssertTrue(editor.contains("ToolbarItemGroup(placement: .principal)"))
        XCTAssertTrue(editor.contains("ToolbarItemGroup(placement: .primaryAction)"))
        XCTAssertTrue(editor.contains(".zoomPercent"))
        XCTAssertTrue(editor.contains("camera.chrome.zoomPercent"))
        XCTAssertEqual(editor.components(separatedBy: "canEnclose(").count - 1, 1)
        XCTAssertTrue(editor.contains("private func linkCommandMenu"))
        XCTAssertFalse(editor.contains("private func viewModeCommandMenu"))
        XCTAssertTrue(editor.contains("overflowAlwaysCommandButton(.mapMode)"))
        XCTAssertTrue(editor.contains("overflowAlwaysCommandButton(.focusMode)"))
        XCTAssertTrue(editor.contains("overflowAlwaysCommandButton(.newCanvas)"))
        // Insert stays in the overflow menu. A toolbar `macItem(.insert)` is the
        // separate plus button this polish removed.
        let macToolbarIDs = (EditorToolbarCatalog.defaultToolbarItems + EditorToolbarCatalog.addableToolbarItems)
            .filter { $0 != .insert }
        for id in macToolbarIDs {
            XCTAssertTrue(editor.contains("macItem(.\(id.rawValue))"), id.rawValue)
        }
        XCTAssertFalse(editor.contains("macItem(.insert)"))
        XCTAssertTrue(editor.contains("insertOverflowSubmenu"))
        for id in [EditorToolbarCommandID.viewMode, .mapMode, .focusMode, .newCanvas] {
            XCTAssertFalse(editor.contains("macItem(.\(id.rawValue))"), id.rawValue)
        }
        for id in EditorToolbarCatalog.menu(.share) {
            XCTAssertFalse(editor.contains("macItem(.\(id.rawValue))"), id.rawValue)
        }
    }

    private func assertSummaryAndBoundary(enabled: Bool, in context: EditorToolbarContext) {
        XCTAssertEqual(EditorToolbarCatalog.isEnabled(.summary, in: context), enabled)
        XCTAssertEqual(EditorToolbarCatalog.isEnabled(.boundary, in: context), enabled)
        XCTAssertTrue(EditorToolbarCatalog.menu(.insert).contains(.summary))
        XCTAssertTrue(EditorToolbarCatalog.menu(.insert).contains(.boundary))
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
