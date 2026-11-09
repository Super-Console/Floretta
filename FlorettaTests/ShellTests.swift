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
        XCTAssertTrue(session.zen.chrome.showsTabBar)
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
        XCTAssertEqual(CanvasMenus.more, ["ZEN", "查找", "新建画布"])
        XCTAssertEqual(CanvasMenus.file, ["重新命名", "导出", "保存至"])
        XCTAssertEqual(CanvasMenus.export, ["floretta", "png", "pdf", "md", "opml", "mm"])
        XCTAssertEqual(CanvasMenus.share, ["导出", "保存至"])
        XCTAssertEqual(CanvasMenus.text, ["剪切", "拷贝", "粘贴", "选择"])
        let visible = CanvasMenus.more + CanvasMenus.file + CanvasMenus.share + CanvasMenus.text
        for name in CanvasMenus.omitted {
            XCTAssertFalse(visible.contains(name))
        }
        let creators = TemplateCatalog.sections.flatMap(\.cards).filter(\.createsDocument)
        XCTAssertEqual(creators.map(\.name), ["思维导图"])
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

    func testVersionTextAndNoticeFallback() {
        XCTAssertEqual(AppInfo.versionText(short: "1.2", build: "9"), "1.2 (9)")
        XCTAssertEqual(AppInfo.versionText(short: nil, build: nil), "1.0")
        XCTAssertTrue(AppInfo.fallbackNotice.contains("SwiftFlow"))
        XCTAssertTrue(AppInfo.fallbackNotice.contains("NOTICE"))
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
