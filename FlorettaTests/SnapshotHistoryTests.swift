import FlorettaCore
import XCTest

final class SnapshotHistoryTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)
    private let rootID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let childID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let otherID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    private let stickyID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    private let linkID = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testListIsOldestFirstAndEmptyUntilTheSecondSave() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        let first = map(title: "第一", root: "根", modifiedAt: stamped)
        try FlorettaStreamingDocument.save(document: first, to: url, files: files)
        let only = SnapshotHistorySession(url: url, live: first, files: files)
        XCTAssertNil(only.loadError)
        XCTAssertEqual(only.snapshots, [])
        XCTAssertEqual(only.current.title, "第一")

        let second = map(title: "第二", root: "改过", modifiedAt: stamped.addingTimeInterval(60), children: [
            MindMapNode(id: childID, text: "子"),
        ])
        try FlorettaStreamingDocument.save(document: second, to: url, files: files)
        let history = SnapshotHistorySession(url: url, live: second, files: files)
        XCTAssertEqual(history.snapshots.map(\.title), ["第一"])
        XCTAssertEqual(history.snapshots.map(\.rootText), ["根"])
        XCTAssertEqual(history.snapshots.map(\.topicCount), [1])
        XCTAssertEqual(history.snapshots.map(\.modifiedAt), [stamped])
        XCTAssertEqual(history.snapshots.map(\.generation), [1])
    }

    @MainActor
    func testRollbackRestoresTheChosenSnapshotAndKeepsTheCurrentOne() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        try FlorettaStreamingDocument.save(document: map(title: "第一", root: "根"), to: url, files: files)
        try FlorettaStreamingDocument.save(document: map(title: "第二", root: "改过"), to: url, files: files)
        try FlorettaStreamingDocument.save(document: map(title: "第三", root: "再改"), to: url, files: files)
        let history = SnapshotHistorySession(url: url, live: map(title: "第三", root: "再改"), files: files)
        XCTAssertEqual(history.snapshots.map(\.title), ["第一", "第二"])

        let oldest = try XCTUnwrap(history.snapshots.first)
        let rolled = try history.rollback(to: oldest.generation, live: history.current)
        XCTAssertEqual(rolled.document.title, "第一")
        XCTAssertEqual(rolled.document.roots.first?.text, "根")
        XCTAssertEqual(history.current.title, "第一")
        XCTAssertTrue(history.snapshots.map(\.title).contains("第三"))

        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        try reader.close()
        XCTAssertEqual(opened.document.title, "第一")
        XCTAssertEqual(opened.document.formatVersion, 1)
    }

    @MainActor
    func testRollbackOfAMissingGenerationDoesNotWrite() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        let current = map(title: "第二", root: "改过")
        try FlorettaStreamingDocument.save(document: map(title: "第一", root: "根"), to: url, files: files)
        try FlorettaStreamingDocument.save(document: current, to: url, files: files)
        let before = try Data(contentsOf: url)
        let history = SnapshotHistorySession(url: url, live: current, files: files)
        XCTAssertThrowsError(try history.rollback(to: 999, live: current)) { error in
            XCTAssertEqual(error as? DocumentOpenError, .message("找不到这一版。"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(history.current.title, "第二")
    }

    @MainActor
    func testRollbackKeepsUnsavedEditsInTheHistory() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        try FlorettaStreamingDocument.save(document: map(title: "第一", root: "根"), to: url, files: files)
        let saved = map(title: "第二", root: "改过")
        try FlorettaStreamingDocument.save(document: saved, to: url, files: files)
        var unsaved = saved
        unsaved.title = "未写盘"
        unsaved.roots[0].text = "还在内存里"
        let history = SnapshotHistorySession(url: url, live: unsaved, files: files)
        let oldest = try XCTUnwrap(history.snapshots.first)
        let rolled = try history.rollback(to: oldest.generation, live: unsaved)
        XCTAssertEqual(rolled.document.title, "第一")
        XCTAssertTrue(history.snapshots.contains { $0.title == "未写盘" && $0.rootText == "还在内存里" })
    }

    @MainActor
    func testRollbackAtTheRetentionEdgeStillRestoresTheOldest() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        for index in 1...9 {
            try FlorettaStreamingDocument.save(
                document: map(title: "v\(index)", root: "根\(index)"),
                to: url,
                files: files
            )
        }
        let onDisk = map(title: "v9", root: "根9")
        let history = SnapshotHistorySession(url: url, live: onDisk, files: files)
        XCTAssertEqual(history.snapshots.count, SnapshotRetention.standard.limit)
        let oldest = try XCTUnwrap(history.snapshots.first)
        XCTAssertEqual(oldest.title, "v1")
        var unsaved = onDisk
        unsaved.title = "未写盘"
        let rolled = try history.rollback(to: oldest.generation, live: unsaved)
        XCTAssertEqual(rolled.document.title, "v1")
        XCTAssertEqual(rolled.document.roots.first?.text, "根1")
        XCTAssertTrue(history.snapshots.contains { $0.title == "未写盘" })
    }

    @MainActor
    func testCompareReportsAddedRemovedAndChangedText() {
        let older = map(title: "第一", root: "根")
        var newer = map(title: "第二", root: "新根", children: [
            MindMapNode(id: childID, text: "子"),
        ])
        newer.roots[0].note = "备注"
        let changes = SnapshotOutlineDiff.changes(from: older, to: newer)
        XCTAssertTrue(changes.contains { $0.role == .documentTitle && $0.before == "第一" && $0.after == "第二" })
        XCTAssertTrue(changes.contains { $0.id == rootID.uuidString && $0.kind == .changed && $0.before == "根" && $0.after == "新根" })
        XCTAssertTrue(changes.contains { $0.id == childID.uuidString && $0.kind == .added && $0.role == .topic && $0.after == "子" && $0.path == "新根 / 子" })
        XCTAssertTrue(changes.contains { $0.role == .note && $0.kind == .changed && $0.after == "备注" })

        let removed = SnapshotOutlineDiff.changes(from: newer, to: older)
        XCTAssertTrue(removed.contains { $0.id == childID.uuidString && $0.kind == .removed && $0.before == "子" })
        XCTAssertEqual(SnapshotOutlineDiff.changes(from: older, to: older), [])
    }

    @MainActor
    func testCompareReportsChildOrderStickyAndRelationship() {
        let root = MindMapNode(id: rootID, text: "根", children: [
            MindMapNode(id: childID, text: "甲"),
            MindMapNode(id: otherID, text: "乙"),
        ])
        var older = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [root],
            relationships: [TopicRelationship(id: linkID, sourceID: rootID, targetID: childID, title: "旧")],
            stickies: [StickyNote(id: stickyID, text: "记", color: .yellow, origin: MindMapPoint(x: 0, y: 0))]
        )
        var newer = older
        newer.roots[0].children.swapAt(0, 1)
        newer.relationships[0].title = "新"
        newer.stickies[0].color = .pink
        let changes = SnapshotOutlineDiff.changes(from: older, to: newer)
        let order = changes.first { $0.role == .childOrder }
        XCTAssertEqual(order?.before, "甲 / 乙")
        XCTAssertEqual(order?.after, "乙 / 甲")
        XCTAssertEqual(order?.kind, .changed)
        let link = changes.first { $0.role == .relationship }
        XCTAssertEqual(link?.before, "根 → 甲 · 旧")
        XCTAssertEqual(link?.after, "根 → 甲 · 新")
        let sticky = changes.first { $0.role == .sticky }
        XCTAssertEqual(sticky?.beforeKey, "黄色")
        XCTAssertEqual(sticky?.afterKey, "粉色")
        XCTAssertEqual(sticky?.before, "记")
        XCTAssertEqual(sticky?.after, "记")
    }

    @MainActor
    func testSessionCompareUsesTwoSnapshotsOrTheCurrentMap() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        let first = map(title: "第一", root: "根")
        let second = map(title: "第二", root: "改过", children: [MindMapNode(id: childID, text: "子")])
        try FlorettaStreamingDocument.save(document: first, to: url, files: files)
        try FlorettaStreamingDocument.save(document: second, to: url, files: files)
        let history = SnapshotHistorySession(url: url, live: second, files: files)
        let generation = try XCTUnwrap(history.snapshots.first?.generation)
        let againstCurrent = history.diff(from: .generation(generation), to: .current)
        XCTAssertTrue(againstCurrent.contains { $0.id == childID.uuidString && $0.kind == .added })
        XCTAssertEqual(history.diff(from: .current, to: .current), [])
        XCTAssertEqual(history.diff(from: .generation(404), to: .current), [])

        let third = map(title: "第三", root: "再改")
        try FlorettaStreamingDocument.save(document: third, to: url, files: files)
        try history.reload(live: third)
        XCTAssertEqual(history.snapshots.map(\.title), ["第一", "第二"])
        let between = history.diff(
            from: .generation(history.snapshots[0].generation),
            to: .generation(history.snapshots[1].generation)
        )
        XCTAssertTrue(between.contains { $0.id == childID.uuidString && $0.kind == .added && $0.after == "子" })
        XCTAssertFalse(between.contains { $0.after == "再改" })
    }

    @MainActor
    func testEditorUndoDoesNotReverseASnapshotRollback() throws {
        let url = try makeDocumentURL()
        let files = FoundationStreamingFiles()
        let first = map(title: "第一", root: "根")
        var second = map(title: "第二", root: "改过")
        try FlorettaStreamingDocument.save(document: first, to: url, files: files)
        try FlorettaStreamingDocument.save(document: second, to: url, files: files)
        let editor = EditorSession(document: second, url: url, sourceExtension: "floretta", viewMode: .map)
        editor.commitText("画布上的字")
        XCTAssertEqual(editor.document.roots[0].text, "画布上的字")
        let history = SnapshotHistorySession(url: url, live: editor.document, files: files)
        let oldest = try XCTUnwrap(history.snapshots.first)
        editor.prepareToSave()
        let rolled = try history.rollback(to: oldest.generation, live: editor.document)
        editor.replaceFromSnapshot(rolled.document, catalog: rolled.catalog, bytes: rolled.byteCount)
        XCTAssertEqual(editor.document.title, "第一")
        XCTAssertEqual(editor.document.roots[0].text, "根")
        editor.undo()
        editor.redo()
        XCTAssertEqual(editor.document.title, "第一")
        XCTAssertEqual(editor.document.roots[0].text, "根")
        XCTAssertEqual(editor.keyboard.selectedNodeID, first.roots[0].id)
    }

    @MainActor
    func testSnapshotHistoryIsUnavailableWithoutAFlorettaFile() {
        let document = map(title: "第一", root: "根")
        let markdown = EditorSession(
            document: document,
            url: URL(fileURLWithPath: "/tmp/note.md"),
            sourceExtension: "md",
            viewMode: .map,
            markdownDocument: true
        )
        XCTAssertFalse(markdown.canOpenSnapshotHistory)
        let unsaved = EditorSession(document: document, url: nil, sourceExtension: "floretta", viewMode: .map)
        XCTAssertFalse(unsaved.canOpenSnapshotHistory)
        let saved = EditorSession(
            document: document,
            url: URL(fileURLWithPath: "/tmp/map.floretta"),
            sourceExtension: "floretta",
            viewMode: .map
        )
        XCTAssertTrue(saved.canOpenSnapshotHistory)
    }

    private func map(
        title: String,
        root: String,
        modifiedAt: Date? = nil,
        children: [MindMapNode] = []
    ) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: stamped,
            modifiedAt: modifiedAt ?? stamped,
            roots: [MindMapNode(id: rootID, text: root, children: children)]
        )
    }

    private func makeDocumentURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaSnapshotHistoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory.appendingPathComponent("map.floretta")
    }
}
