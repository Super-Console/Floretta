import CoreGraphics
import FlorettaCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ShellTests: XCTestCase {
    func testZoomStopsAreTheIntegerPercents() {
        XCTAssertEqual(
            ZoomStop.legalPercents,
            [50, 75, 100, 125, 150, 200, 300, 400]
        )
        for stop in ZoomStop.allCases {
            XCTAssertEqual(stop.percent, Int(stop.scale * 100))
            XCTAssertEqual(stop.percent % 1, 0)
        }
    }

    func testOneHundredPercentScaleIsExactlyOne() {
        XCTAssertEqual(ZoomStop.oneHundred.scale, 1)
        XCTAssertTrue(ZoomStop.oneHundred.scale == CGFloat(1))
        var viewport = CanvasViewport()
        XCTAssertEqual(viewport.scale, ZoomStop.oneHundred.scale)
        viewport.zoom(to: ZoomStop.oneHundred.scale, around: CGPoint(x: 120, y: 80))
        XCTAssertEqual(viewport.scale, 1)
    }

    func testSnapAndDisplayPercentAlwaysLandOnALegalStop() {
        let samples: [CGFloat] = [
            -10, -0.2, 0, 0.01, 0.5, 0.62, 0.63, 0.874, 1, 1.125, 1.37, 1.999,
            2.4, 3.6, 4, 9, .nan, .infinity, -.infinity,
        ]
        for sample in samples {
            let stop = ZoomStop.nearest(to: sample)
            XCTAssertTrue(ZoomStop.allCases.contains(stop))
            let shown = ZoomStop.displayPercent(forScale: sample)
            XCTAssertEqual(shown, stop.percent)
            XCTAssertTrue(ZoomStop.legalPercents.contains(shown))
            XCTAssertNotEqual(shown, 137)
        }
        var scale = CGFloat(-1)
        while scale <= 6 {
            let shown = ZoomStop.displayPercent(forScale: scale)
            XCTAssertTrue(ZoomStop.legalPercents.contains(shown), "\(scale) showed \(shown)")
            scale += 0.01
        }
        XCTAssertEqual(ZoomStop.displayPercent(forScale: 1.37), 125)
        XCTAssertNotEqual(ZoomStop.displayPercent(forScale: 1.37), 137)
        XCTAssertEqual(ZoomStop.nearest(to: 1.125), .oneHundred)
        XCTAssertEqual(ZoomStop.oneHundred.stepped(1), .oneTwentyFive)
        XCTAssertEqual(ZoomStop.oneHundred.stepped(-1), .seventyFive)
        XCTAssertEqual(ZoomStop.fifty.stepped(-1), .fifty)
        XCTAssertEqual(ZoomStop.fourHundred.stepped(1), .fourHundred)

        var chrome = CanvasChrome.standard
        chrome.syncZoomPercent(toScale: 1.37)
        XCTAssertEqual(chrome.zoomPercent, 125)
        XCTAssertNotEqual(chrome.zoomPercent, 137)
        XCTAssertTrue(ZoomStop.legalPercents.contains(chrome.zoomPercent))
    }

    func testViewportSnapAndCommandScrollUseLegalStops() {
        var viewport = CanvasViewport()
        viewport.zoom(to: 1.37, around: CGPoint(x: 80, y: 60))
        viewport.snapToStop(around: CGPoint(x: 80, y: 60))
        XCTAssertEqual(viewport.scale, ZoomStop.nearest(to: 1.37).scale, accuracy: 0.000_1)
        XCTAssertTrue(ZoomStop.allCases.contains { abs($0.scale - viewport.scale) < 0.000_1 })

        var scrolled = CanvasViewport()
        scrolled.applyScroll(
            delta: CGSize(width: 0, height: 100),
            around: CGPoint(x: 40, y: 40),
            command: true
        )
        XCTAssertGreaterThan(scrolled.scale, 1)
        XCTAssertTrue(ZoomStop.allCases.contains { abs($0.scale - scrolled.scale) < 0.000_1 })
        XCTAssertNotEqual(ZoomStop.displayPercent(forScale: scrolled.scale), 137)
    }

    func testZenEnterAndExitRestoreDocumentAndSelection() {
        let id = UUID()
        let session = EditorSession(
            document: MindMapDocument(title: "zen", roots: [MindMapNode(id: id, text: "根")]),
            url: nil,
            sourceExtension: "floretta",
            viewMode: .map
        )
        let before = session.document
        XCTAssertEqual(session.keyboard.selectedNodeID, id)
        XCTAssertEqual(session.zen.chrome, .editing)

        session.enterZen()
        XCTAssertTrue(session.zen.isActive)
        XCTAssertEqual(session.zen.chrome, .hidden)
        XCTAssertFalse(session.zen.chrome.showsToolbar)
        XCTAssertFalse(session.zen.chrome.showsTabBar)
        XCTAssertFalse(session.zen.chrome.showsStatusBar)
        XCTAssertFalse(session.zen.chrome.showsSidebar)
        XCTAssertFalse(session.zen.chrome.showsInspector)
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.keyboard.selectedNodeID, id)

        XCTAssertTrue(session.handleEscape())
        XCTAssertFalse(session.zen.isActive)
        XCTAssertEqual(session.zen.chrome, .editing)
        XCTAssertTrue(session.zen.chrome.showsToolbar)
        XCTAssertFalse(session.zen.chrome.showsTabBar)
        XCTAssertTrue(session.zen.chrome.showsStatusBar)
        XCTAssertTrue(session.zen.chrome.showsSidebar)
        XCTAssertTrue(session.zen.chrome.showsInspector)
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.keyboard.selectedNodeID, id)

        session.enterZen()
        XCTAssertTrue(session.consumeBlankDoubleTap())
        XCTAssertFalse(session.zen.isActive)
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.keyboard.selectedNodeID, id)
        XCTAssertFalse(session.consumeBlankDoubleTap())
        XCTAssertFalse(session.handleEscape())
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.keyboard.selectedNodeID, id)
    }

    func testSettingsRoundTripAndDriveExportAndNewDocuments() throws {
        let defaults = try freshDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.defaultView, .map)
        XCTAssertEqual(settings.pngScale, .two)
        XCTAssertEqual(settings.pngBackground, .white)
        XCTAssertNil(settings.appearance.colorScheme)

        settings.language = .simplifiedChinese
        settings.appearance = .dark
        settings.defaultView = .focus
        settings.pngScale = .one
        settings.pngBackground = .transparent

        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.language, .simplifiedChinese)
        XCTAssertTrue(again.resolvedLocale.identifier.lowercased().hasPrefix("zh"))
        XCTAssertEqual(again.appearance, .dark)
        XCTAssertEqual(again.appearance.colorScheme, .dark)
        again.appearance = .light
        XCTAssertEqual(again.appearance.colorScheme, .light)
        again.appearance = .system
        XCTAssertNil(again.appearance.colorScheme)
        again.language = .english
        XCTAssertTrue(again.resolvedLocale.identifier.lowercased().hasPrefix("en"))
        XCTAssertEqual(again.defaultView, .focus)
        XCTAssertEqual(again.pngScale, .one)
        XCTAssertEqual(again.pngBackground, .transparent)

        let options = MapExportOptions(settings: again)
        XCTAssertEqual(options.scale, .one)
        XCTAssertEqual(options.scale.rawValue, 1)
        XCTAssertEqual(options.background, .transparent)

        let document = MindMapDocument(
            title: "export",
            roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])]
        )
        let one = MapExporter.png(document: document, settings: again)
        XCTAssertNotNil(one.png)
        XCTAssertGreaterThan(one.png?.count ?? 0, 0)
        XCTAssertEqual(one.pixelSize.width, one.pointSize.width * options.scale.rawValue, accuracy: 4)
        XCTAssertEqual(one.pixelSize.height, one.pointSize.height * options.scale.rawValue, accuracy: 4)

        again.pngScale = .two
        again.pngBackground = .white
        let two = MapExporter.png(document: document, settings: again)
        XCTAssertEqual(MapExportOptions(settings: again).scale, .two)
        XCTAssertEqual(MapExportOptions(settings: again).background, .white)
        XCTAssertEqual(two.pixelSize.width, one.pixelSize.width * 2, accuracy: 8)

        let directory = try temporaryDirectory()
        let library = LibraryModel(
            settings: again,
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: directory
        )
        library.makeNew()
        XCTAssertEqual(library.editor?.viewMode, .focus)
        XCTAssertNotNil(library.editor)
        again.defaultView = .map
        library.closeEditor()
        library.makeNew()
        XCTAssertEqual(library.editor?.viewMode, .map)
    }

    func testColdStartDoesNotScanAndOpenCloseFillsRecents() throws {
        let directory = try temporaryDirectory()
        try Data("ignore".utf8).write(to: directory.appendingPathComponent("other.txt"))
        let defaults = try freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let library = LibraryModel(
            settings: settings,
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: directory
        )
        XCTAssertNil(library.editor)
        XCTAssertTrue(library.recents.isEmpty)

        let url = directory.appendingPathComponent("sample.mm")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
        <node TEXT="根"/>
        </map>
        """
        try Data(xml.utf8).write(to: url)
        library.openFile(url)
        XCTAssertNil(library.openError)
        XCTAssertEqual(library.editor?.document.roots.first?.text, "根")
        XCTAssertNotNil(library.editor)
        XCTAssertFalse(library.closeEditor())
        XCTAssertNil(library.editor)
        XCTAssertEqual(library.recents.map(\.filename), ["sample.mm"])

        library.makeNew()
        XCTAssertNotNil(library.editor?.url)
        XCTAssertTrue(library.closeEditor())
        XCTAssertNil(library.editor)
        XCTAssertEqual(library.recents.count, 2)
        XCTAssertTrue(library.recents.contains { $0.filename.hasSuffix(".floretta") })
        XCTAssertFalse(library.recents.contains { $0.filename == "other.txt" })
    }

    func testFileTypesAreOnlyTheSupportedFormats() {
        XCTAssertEqual(
            FlorettaFileTypes.allowedIdentifiers,
            [
                "net.timhuang.floretta.document",
                "org.freemind.mm",
                "org.opml.opml",
                "net.daringfireball.markdown",
            ]
        )
        XCTAssertEqual(FlorettaFileTypes.allowedExtensions, ["floretta", "mm", "opml", "md"])
    }

    func testMarkdownRoundTripAndUnsupportedLineFails() throws {
        let child = MindMapNode(text: "子", note: "子备注", link: "https://example.com/a")
        let root = MindMapNode(text: "根", note: "根备注\n第二行", children: [child])
        let document = MindMapDocument(title: "md", roots: [root])
        let imported = try FlorettaMarkdown.importOutline(Data(FlorettaMarkdown.export(document).utf8))
        XCTAssertEqual(imported.roots.count, 1)
        XCTAssertEqual(imported.roots[0].text, "根")
        XCTAssertEqual(imported.roots[0].note, "根备注\n第二行")
        XCTAssertEqual(imported.roots[0].children.count, 1)
        XCTAssertEqual(imported.roots[0].children[0].text, "子")
        XCTAssertEqual(imported.roots[0].children[0].note, "子备注")
        XCTAssertEqual(imported.roots[0].children[0].link, "https://example.com/a")
        XCTAssertThrowsError(try DocumentOpener.open(data: Data("hello".utf8), filename: "note.md"))
        XCTAssertThrowsError(try DocumentOpener.open(data: Data("nope".utf8), filename: "map.txt"))
    }

    func testMapFilesAreNotImportedAsMarkdown() throws {
        let map = MindMapDocument(title: "图", roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])])
        let mm = try DocumentOpener.open(data: try FlorettaMMCodec.export(map), filename: "notes.md")
        XCTAssertEqual(mm.roots.first?.text, "根")
        XCTAssertEqual(mm.roots.first?.children.first?.text, "子")
        let opml = try DocumentOpener.open(data: try FlorettaOPMLCodec.export(map), filename: "notes.md")
        XCTAssertEqual(opml.title, "图")
        XCTAssertEqual(opml.roots.first?.text, "根")
        let floretta = try DocumentOpener.open(data: try FlorettaCodec.encode(map), filename: "notes.md")
        XCTAssertEqual(floretta.roots.first?.text, "根")
    }

    func testFocusModeHidesTheRestOfTheTree() {
        let parent = UUID()
        let child = UUID()
        let other = UUID()
        let document = MindMapDocument(
            title: "focus",
            roots: [
                MindMapNode(id: parent, text: "根", children: [MindMapNode(id: child, text: "子")]),
                MindMapNode(id: other, text: "另"),
            ]
        )
        let focused = FocusLayout.visibleIDs(document, focus: child)
        XCTAssertEqual(focused, [child])
        XCTAssertFalse(focused.contains(parent))
        XCTAssertFalse(focused.contains(other))
        let whole = FocusLayout.visibleIDs(document, focus: nil)
        XCTAssertTrue(whole.contains(parent))
        XCTAssertTrue(whole.contains(child))
        XCTAssertTrue(whole.contains(other))
        XCTAssertEqual(FocusLayout.chain(document, to: child).map(\.id), [parent, child])
    }

    func testFindAndReopenKeepAFreeNode() throws {
        var document = MindMapDocument(title: "图", roots: [MindMapNode(text: "根")])
        let id = document.addFreeNode(text: "海边", at: MindMapPoint(x: 12, y: -4))
        XCTAssertEqual(CanvasEditCommands.find(in: document, query: "海"), id)
        XCTAssertEqual(document.topicCount, 2)
        let data = try SharePayload.bytes(for: "xmind", document: document)
        let opened = try DocumentOpener.open(data: data, filename: "图.xmind")
        XCTAssertEqual(opened.freeNodes.map(\.id), [id])
        XCTAssertEqual(opened.freeNodes[0].text, "海边")
        XCTAssertEqual(opened.freeNodes[0].position, MindMapPoint(x: 12, y: -4))
        XCTAssertFalse(opened.roots.contains { $0.id == id })
    }

    func testFillColorSurvivesEncodeDecodeAndLayout() throws {
        let id = UUID()
        var document = MindMapDocument(title: "style", roots: [MindMapNode(id: id, text: "根")])
        XCTAssertTrue(CanvasEditCommands.setFill(hex: "#E23D3D", nodeID: id, document: &document))
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded.roots[0].style?.fillHex, "#E23D3D")
        let frame = try XCTUnwrap(LayoutEngine().layout(decoded).first { $0.id == id })
        let color = try XCTUnwrap(BranchColor(hex: "#E23D3D"))
        XCTAssertEqual(frame.fill.red, color.red, accuracy: 0.001)
        XCTAssertEqual(frame.fill.green, color.green, accuracy: 0.001)
        XCTAssertEqual(frame.fill.blue, color.blue, accuracy: 0.001)

        var sized = decoded
        XCTAssertTrue(sized.mutateNode(id) { node in
            node.style?.fontSize = 28
            node.style?.borderHex = "#112233"
        })
        let again = try FlorettaCodec.decode(try FlorettaCodec.encode(sized))
        XCTAssertEqual(again.roots[0].style?.fontSize, 28)
        XCTAssertEqual(again.roots[0].style?.borderHex, "#112233")
        let sizedFrame = try XCTUnwrap(LayoutEngine().layout(again).first { $0.id == id })
        XCTAssertEqual(sizedFrame.fontSize, 28, accuracy: 0.001)

        let legacy = MindMapDocument(
            title: "old",
            roots: [MindMapNode(text: "a", style: MindMapNodeStyle(colorHex: "#C45C26"))]
        )
        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(legacy), encoding: .utf8))
        XCTAssertTrue(json.contains("#C45C26"))
        XCTAssertFalse(json.contains("fillHex"))
    }

    func testMenusAndTemplatesOmitDeadActions() {
        XCTAssertEqual(CanvasMenus.immersive, "全屏沉浸")
        XCTAssertEqual(CanvasMenus.insert, ["子节点", "同级", "自由节点", "连到", "图片", "附件", "从文件导入"])
        XCTAssertEqual(
            CanvasMenus.zoom,
            ["50%", "75%", "100%", "125%", "150%", "200%", "300%", "400%", "适应窗口"]
        )
        XCTAssertEqual(ZoomStop.allCases.map { "\($0.percent)%" }, Array(CanvasMenus.zoom.dropLast()))
        XCTAssertEqual(CanvasMenus.more, ["大纲", "样式", "查看模式", "新建画布", "查找", "粘贴", "关于"])
        XCTAssertEqual(CanvasMenus.moreDisabled, [])
        XCTAssertFalse(CanvasMenus.more.contains("ZEN"))
        XCTAssertFalse(CanvasMenus.more.contains("Zen"))
        XCTAssertEqual(CanvasMenus.file, ["重新命名"])
        XCTAssertEqual(CanvasMenus.fileDisabled, [])
        XCTAssertEqual(CanvasMenus.export, ["floretta", "mm", "opml", "md", "png", "pdf", "xmind"])
        XCTAssertEqual(CanvasMenus.share, ["PDF", "PNG", "Markdown", "保存为 Floretta", ".mm", "OPML", ".xmind", "打印"])
        XCTAssertEqual(CanvasMenus.text, ["剪切", "拷贝", "粘贴", "全选", "拷贝样式"])
        XCTAssertEqual(CanvasMenus.textDisabled, [])
        let visible = CanvasMenus.more + CanvasMenus.file + CanvasMenus.share + CanvasMenus.text + CanvasMenus.export
        for name in CanvasMenus.omitted {
            XCTAssertFalse(visible.contains(name))
        }
        XCTAssertEqual(TemplateCatalog.sections.map(\.title), ["结构", "分析", "记录"])
        let cards = TemplateCatalog.sections.flatMap(\.cards)
        XCTAssertEqual(cards.count, 12)
        XCTAssertTrue(cards.allSatisfy(\.createsDocument))
        XCTAssertEqual(Set(cards.map(\.name)).count, cards.count)
        let shapes = cards.map { TemplateKind.shape($0.kind.document()) }
        XCTAssertEqual(Set(shapes).count, shapes.count)
        XCTAssertFalse(cards.map(\.name).contains("即将推出"))
        XCTAssertTrue(ShellTab.homeOverflowTitles.isEmpty)
    }

    func testSecondTapOnTheSelectedNodeStartsEditing() {
        let id = UUID()
        let other = UUID()
        XCTAssertEqual(
            NodeEditTap.action(hit: id, selected: nil, mode: .command, isComposing: false),
            .select(id)
        )
        XCTAssertEqual(
            NodeEditTap.action(hit: id, selected: id, mode: .command, isComposing: false),
            .beginEdit(id)
        )
        XCTAssertEqual(
            NodeEditTap.action(hit: id, selected: id, mode: .edit, isComposing: false),
            .ignore
        )
        XCTAssertEqual(
            NodeEditTap.action(hit: other, selected: id, mode: .edit, isComposing: false),
            .commitAndSelect(other)
        )
        XCTAssertEqual(
            NodeEditTap.action(hit: id, selected: id, mode: .edit, isComposing: true),
            .ignore
        )
    }

    func testUndoAndDeleteWorkWhileTheNewNodeIsStillBeingEdited() {
        let root = UUID()
        let session = EditorSession(
            document: MindMapDocument(title: "编辑", roots: [MindMapNode(id: root, text: "根")]),
            url: nil,
            sourceExtension: "floretta",
            viewMode: .map
        )
        session.addChildFromToolbar()
        XCTAssertEqual(session.document.node(root)?.children.count, 1)
        XCTAssertEqual(session.keyboard.mode, .edit)
        session.undo()
        XCTAssertEqual(session.document.node(root)?.children.count, 0)

        session.addChildFromToolbar()
        session.addSiblingFromToolbar()
        XCTAssertEqual(session.document.node(root)?.children.count, 2)
        session.deleteSelection()
        XCTAssertEqual(session.document.node(root)?.children.count, 1)
        session.undo()
        XCTAssertEqual(session.document.node(root)?.children.count, 2)
        session.redo()
        XCTAssertEqual(session.document.node(root)?.children.count, 1)
    }

    func testLocalBrowseListsOnlySupportedFilesInThatDirectory() throws {
        let directory = try temporaryDirectory()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).mm")
        try Data("<map/>".utf8).write(to: outside)
        try Data("map".utf8).write(to: directory.appendingPathComponent("map.mm"))
        try Data("note".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let defaults = try freshDefaults()
        let library = LibraryModel(
            settings: AppSettings(defaults: defaults),
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: directory
        )
        XCTAssertEqual(library.files(in: directory).map(\.lastPathComponent), ["map.mm"])
        try? FileManager.default.removeItem(at: outside)
    }

    func testLocalDeviceLabelIsDeviceAware() {
        XCTAssertEqual(
            LocalDeviceLabel.make(for: .iPhone),
            LocalDeviceLabel(title: "我的 iPhone", systemImage: "iphone")
        )
        XCTAssertEqual(
            LocalDeviceLabel.make(for: .iPad),
            LocalDeviceLabel(title: "我的 iPad", systemImage: "ipad")
        )
        XCTAssertEqual(
            LocalDeviceLabel.make(for: .mac),
            LocalDeviceLabel(title: "我的 Mac", systemImage: "macbook")
        )
        let titles = [
            LocalDeviceLabel.make(for: .iPhone).title,
            LocalDeviceLabel.make(for: .iPad).title,
            LocalDeviceLabel.make(for: .mac).title,
        ]
        XCTAssertEqual(Set(titles).count, titles.count)
        #if os(macOS)
        XCTAssertEqual(LocalDeviceLabel.currentKind, .mac)
        XCTAssertEqual(LocalDeviceLabel.current, LocalDeviceLabel.make(for: .mac))
        #endif
    }

    func testVersionTextAndNoticeFallback() {
        XCTAssertEqual(AppInfo.versionText(short: "1.2", build: "9"), "1.2 (9)")
        XCTAssertEqual(AppInfo.versionText(short: nil, build: nil), "1.0")
        XCTAssertTrue(AppInfo.fallbackNotice.contains("SwiftFlow"))
        XCTAssertTrue(AppInfo.fallbackNotice.contains("NOTICE"))
    }

    func testExportTypesStayInTheReadableList() {
        XCTAssertEqual(FlorettaFileTypes.contentType(forExport: "png"), .png)
        XCTAssertEqual(FlorettaFileTypes.contentType(forExport: "pdf"), .pdf)
        XCTAssertNotEqual(FlorettaFileTypes.contentType(forExport: "md"), .png)
        XCTAssertNotEqual(FlorettaFileTypes.contentType(forExport: "md"), .pdf)
        XCTAssertNotEqual(FlorettaFileTypes.contentType(forExport: "opml"), .png)
        XCTAssertNotEqual(FlorettaFileTypes.contentType(forExport: "mm"), .pdf)
        for kind in FlorettaFileTypes.exportKinds {
            let type = FlorettaFileTypes.contentType(forExport: kind)
            XCTAssertTrue(FlorettaFileTypes.exportableContentTypes.contains(type), kind)
            if let declared = declaredExportType(kind) {
                XCTAssertEqual(type, declared, kind)
            }
        }
        XCTAssertTrue(FlorettaFileTypes.allowedContentTypes.contains(.xml))
        XCTAssertTrue(FlorettaFileTypes.allowedContentTypes.contains(.plainText))
    }

    func testEditFieldTapDoesNotDismissChineseInput() {
        let field = CGRect(x: 10, y: 10, width: 88, height: 36)
        XCTAssertTrue(EditFieldGuard.ignoresCanvasTap(at: CGPoint(x: 90, y: 20), editFrame: field, isComposing: false))
        XCTAssertFalse(EditFieldGuard.ignoresCanvasTap(at: CGPoint(x: 0, y: 0), editFrame: field, isComposing: false))
        XCTAssertTrue(EditFieldGuard.ignoresCanvasTap(at: CGPoint(x: 0, y: 0), editFrame: nil, isComposing: true))
        XCTAssertFalse(EditFieldGuard.ignoresCanvasTap(at: CGPoint(x: 0, y: 0), editFrame: nil, isComposing: false))
        XCTAssertEqual(
            NodeEditTap.action(hit: nil, selected: UUID(), mode: .edit, isComposing: true),
            .ignore
        )
    }

    func testBasicChainSaveReopenExportImportAndExit() throws {
        let directory = try temporaryDirectory()
        let library = try makeLibrary(directory: directory)
        library.makeNew()
        let session = try XCTUnwrap(library.editor)
        session.document.title = "中文图"
        session.keyboard.selectedNodeID = session.document.roots[0].id
        session.commitText("中文")
        session.addChildFromToolbar()
        session.commitText("子节点")
        session.addSiblingFromToolbar()
        session.commitText("同级")
        session.deleteSelection()
        XCTAssertEqual(session.document.roots[0].children.map(\.text), ["子节点"])
        session.undo()
        XCTAssertEqual(session.document.roots[0].children.map(\.text), ["子节点", "同级"])
        session.redo()
        XCTAssertEqual(session.document.roots[0].children.map(\.text), ["子节点"])
        session.undo()
        XCTAssertEqual(session.document.roots[0].children.map(\.text), ["子节点", "同级"])

        let savedURL = try XCTUnwrap(session.url)
        XCTAssertTrue(library.closeEditor())
        XCTAssertNil(library.editor)

        library.openFile(savedURL)
        let reopened = try XCTUnwrap(library.editor?.document)
        XCTAssertEqual(reopened.title, "中文图")
        XCTAssertEqual(reopened.roots.first?.text, "中文")
        XCTAssertEqual(reopened.roots.first?.children.map(\.text), ["子节点", "同级"])

        let md = try SharePayload.bytes(for: "md", document: reopened)
        let mm = try SharePayload.bytes(for: "mm", document: reopened)
        let opml = try SharePayload.bytes(for: "opml", document: reopened)
        let fromMD = try DocumentOpener.open(data: md, filename: "笔记.md")
        XCTAssertEqual(fromMD.roots.first?.text, "中文")
        XCTAssertEqual(fromMD.roots.first?.children.map(\.text), ["子节点", "同级"])
        let fromMM = try DocumentOpener.open(data: mm, filename: "notes.md")
        XCTAssertEqual(fromMM.roots.first?.text, "中文")
        XCTAssertEqual(fromMM.roots.first?.children.map(\.text), ["子节点", "同级"])
        let fromOPML = try DocumentOpener.open(data: opml, filename: "notes.md")
        XCTAssertEqual(fromOPML.title, "中文图")
        XCTAssertEqual(fromOPML.roots.first?.text, "中文")
        XCTAssertEqual(fromOPML.roots.first?.children.map(\.text), ["子节点", "同级"])

        let png = MapExporter.png(document: reopened)
        XCTAssertGreaterThan(png.png?.count ?? 0, 8)
        let pdf = MapExporter.pdf(document: reopened)
        let pdfBytes = try XCTUnwrap(pdf.pdf)
        XCTAssertTrue(pdfBytes.starts(with: Data("%PDF".utf8)))

        let opmlURL = directory.appendingPathComponent("导入.opml")
        try opml.write(to: opmlURL)
        library.openFile(opmlURL)
        XCTAssertNil(library.openError)
        XCTAssertEqual(library.editor?.sourceExtension, "opml")
        XCTAssertEqual(library.editor?.document.roots.first?.text, "中文")
        let still = try DocumentOpener.open(data: Data(contentsOf: savedURL), filename: savedURL.lastPathComponent)
        XCTAssertEqual(still.roots.first?.text, "中文")
        XCTAssertEqual(still.roots.first?.children.map(\.text), ["子节点", "同级"])
        XCTAssertFalse(library.closeEditor())
        XCTAssertNil(library.editor)
    }

    func testSaveFailureKeepsTheOpenMap() throws {
        let directory = try temporaryDirectory()
        let gate = WriteGate()
        var ports = ApplePlatformPorts.current()
        ports.files = gate
        ports.streaming = GatedStreaming(gate: gate)
        let library = try makeLibrary(directory: directory, ports: ports)
        library.makeNew()
        let session = try XCTUnwrap(library.editor)
        session.keyboard.selectedNodeID = session.document.roots[0].id
        session.commitText("中文")
        gate.allow = false
        XCTAssertFalse(library.closeEditor())
        XCTAssertNotNil(library.editor)
        XCTAssertEqual(library.alertTitle, "无法保存")
        XCTAssertEqual(library.editor?.document.roots.first?.text, "中文")
        library.makeNew()
        XCTAssertEqual(library.editor?.document.roots.first?.text, "中文")
        gate.allow = true
        XCTAssertTrue(library.closeEditor())
        XCTAssertNil(library.editor)
        XCTAssertNil(library.openError)
        let entry = try XCTUnwrap(library.recents.first { $0.filename.hasSuffix(".floretta") })
        library.openRecent(entry)
        XCTAssertEqual(library.editor?.document.roots.first?.text, "中文")
    }

    func testLegacyJSONCloseWritesANewZipAndLeavesTheOriginal() throws {
        let directory = try temporaryDirectory()
        let legacyURL = directory.appendingPathComponent("旧图.floretta")
        let original = MindMapDocument(title: "旧", roots: [MindMapNode(text: "原文")])
        let bytes = try FlorettaCodec.encode(original)
        try bytes.write(to: legacyURL)
        let library = try makeLibrary(directory: directory)
        library.openFile(legacyURL)
        XCTAssertNil(library.openError)
        let session = try XCTUnwrap(library.editor)
        session.document.roots[0].text = "中文修订"
        XCTAssertTrue(library.closeEditor())
        XCTAssertNil(library.editor)
        XCTAssertEqual(try Data(contentsOf: legacyURL), bytes)
        let created = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "旧图.floretta" && $0.pathExtension == "floretta" }
        XCTAssertEqual(created.count, 1)
        let saved = try DocumentOpener.open(data: Data(contentsOf: created[0]), filename: created[0].lastPathComponent)
        XCTAssertEqual(saved.roots.first?.text, "中文修订")
    }

    func testSaveAsAdoptsFlorettaWhenTheOpenFileIsNotOne() throws {
        let directory = try temporaryDirectory()
        let library = try makeLibrary(directory: directory)
        library.makeNew()
        let original = try XCTUnwrap(library.editor?.url)
        let copy = directory.appendingPathComponent("另存.floretta")
        let snapshot = try XCTUnwrap(library.editor).document
        try SharePayload.bytes(for: "floretta", document: snapshot).write(to: copy)
        library.noteExportedCopy(copy)
        XCTAssertEqual(library.editor?.url?.path, original.path)
        XCTAssertTrue(library.recents.contains { $0.filename == "另存.floretta" })
        XCTAssertTrue(library.closeEditor())

        let mm = directory.appendingPathComponent("图.mm")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1"><node TEXT="根"/></map>
        """
        try Data(xml.utf8).write(to: mm)
        library.openFile(mm)
        XCTAssertEqual(library.editor?.sourceExtension, "mm")
        try SharePayload.bytes(for: "floretta", document: try XCTUnwrap(library.editor).document).write(to: copy)
        library.noteExportedCopy(copy)
        XCTAssertEqual(library.editor?.url?.path, copy.path)
        XCTAssertEqual(library.editor?.sourceExtension, "floretta")
        let adopted = try XCTUnwrap(library.editor)
        adopted.document.roots[0].text = "中文"
        XCTAssertTrue(library.closeEditor())
        let again = try DocumentOpener.open(data: Data(contentsOf: copy), filename: copy.lastPathComponent)
        XCTAssertEqual(again.roots.first?.text, "中文")
        let originalMM = try XCTUnwrap(String(contentsOf: mm, encoding: .utf8))
        XCTAssertTrue(originalMM.contains("根"))
        XCTAssertFalse(originalMM.contains("中文"))
    }

    private func declaredExportType(_ kind: String) -> UTType? {
        switch kind {
        case "png": return .png
        case "pdf": return .pdf
        case "md": return UTType(FlorettaFileTypes.markdownIdentifier)
        case "opml": return UTType(FlorettaFileTypes.opmlIdentifier)
        case "mm": return UTType(FlorettaFileTypes.mmIdentifier)
        case "floretta": return UTType(FlorettaFileTypes.florettaIdentifier)
        case "xmind": return UTType(filenameExtension: "xmind")
        default: return nil
        }
    }

    private func makeLibrary(directory: URL, ports: ApplePlatformPorts = .current()) throws -> LibraryModel {
        let defaults = try freshDefaults()
        return LibraryModel(
            settings: AppSettings(defaults: defaults),
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: directory,
            ports: ports
        )
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "floretta.shell.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class GatedStreaming: StreamingFilePort {
    let gate: WriteGate
    private let inner = FoundationStreamingFiles()

    init(gate: WriteGate) { self.gate = gate }

    func byteCount(at url: URL) throws -> Int64 { try inner.byteCount(at: url) }
    func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
    func isZip(at url: URL) throws -> Bool { try inner.isZip(at: url) }
    func openReader(at url: URL) throws -> RandomAccessReader { try inner.openReader(at: url) }

    func openWriter(at url: URL) throws -> SequentialByteWriter {
        if !gate.allow { throw CocoaError(.fileWriteNoPermission) }
        return try inner.openWriter(at: url)
    }

    func makeTemporary(nextTo url: URL) throws -> URL {
        if !gate.allow { throw CocoaError(.fileWriteNoPermission) }
        return try inner.makeTemporary(nextTo: url)
    }

    func replace(destination: URL, with temporary: URL) throws {
        if !gate.allow { throw CocoaError(.fileWriteNoPermission) }
        try inner.replace(destination: destination, with: temporary)
    }

    func remove(at url: URL) throws { try inner.remove(at: url) }
}

private final class WriteGate: FileAccessPort {
    var allow = true
    private let inner = FoundationFileAccess()

    func read(from url: URL) throws -> Data {
        try inner.read(from: url)
    }

    func write(_ data: Data, to url: URL) throws {
        if !allow {
            throw CocoaError(.fileWriteNoPermission)
        }
        try inner.write(data, to: url)
    }

    func fileExists(at url: URL) -> Bool {
        inner.fileExists(at: url)
    }

    func remove(at url: URL) throws {
        try inner.remove(at: url)
    }
}
