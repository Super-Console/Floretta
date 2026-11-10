import FlorettaCore
import XCTest

final class ShareIngressTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testSafariPageBecomesAChildAndPhotosStayByteIdentical() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("阅读.floretta")
        let center = UUID()
        let reading = UUID()
        let document = MindMapDocument(
            title: "阅读",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: center, text: "中心", children: [
                MindMapNode(id: reading, text: "阅读"),
            ])]
        )
        let files = ShareProbeFiles()
        _ = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, snapshots: .none)

        let page = try ShareDraftBuilder.make(
            origin: .safari,
            url: "https://example.com/notes",
            title: "一篇笔记",
            file: ShareFileFact(filename: "preview.png", byteCount: 12, isDirectory: false)
        )
        XCTAssertEqual(page.kind, .webPage(url: "https://example.com/notes", title: "一篇笔记"))
        let savedPage = try ShareCommit.commit(
            page,
            onto: reading,
            archive: archive,
            files: files,
            now: stamped.addingTimeInterval(60),
            snapshots: .none
        )
        let child = try XCTUnwrap(savedPage.document.node(reading)?.children.last)
        XCTAssertEqual(child.text, "一篇笔记")
        XCTAssertEqual(child.link, "https://example.com/notes")
        XCTAssertEqual(savedPage.childID, child.id)
        XCTAssertFalse(savedPage.storedOnNode)

        let photo = directory.appendingPathComponent("IMG.HEIC")
        let photoBytes = StreamingBudget.chunkBytes + 128
        try writePattern(to: photo, count: photoBytes)
        let photoReader = try files.openReader(at: photo)
        let expected = try FlorettaStreamingDocument.hashSource(photoReader, filename: "IMG.HEIC")
        try photoReader.close()
        files.resetPhotoReads(photo)

        let image = try ShareDraftBuilder.make(
            origin: .photos,
            url: "https://example.com/ignored",
            file: ShareFileFact(filename: "IMG.HEIC", byteCount: Int64(photoBytes), isDirectory: false)
        )
        let savedImage = try ShareCommit.commit(
            image,
            onto: reading,
            archive: archive,
            fileURL: photo,
            files: files,
            now: stamped.addingTimeInterval(120),
            snapshots: .none
        )
        let attachment = try XCTUnwrap(savedImage.attachment)
        XCTAssertEqual(attachment.sha256, expected.sha256)
        XCTAssertEqual(attachment.fileExtension, "heic")
        XCTAssertEqual(attachment.byteCount, Int64(photoBytes))
        XCTAssertEqual(savedImage.document.node(reading)?.attachments, [attachment])
        XCTAssertFalse(savedImage.deduplicated)
        XCTAssertEqual(savedImage.proposal?.exceedsSoftCap, false)
        let entry = try XCTUnwrap(savedImage.directory.attachments.first)
        XCTAssertEqual(entry.method, 0)
        XCTAssertEqual(entry.byteCount, UInt64(photoBytes))
        XCTAssertEqual(entry.name, "assets/\(expected.sha256).heic")
        let exported = directory.appendingPathComponent("out.heic")
        let archiveReader = try files.openReader(at: archive)
        let writer = try files.openWriter(at: exported)
        try FlorettaStreamingDocument.exportAttachment(entry, from: archiveReader, to: writer)
        try writer.close()
        try archiveReader.close()
        let exportedReader = try files.openReader(at: exported)
        let exportedHash = try FlorettaStreamingDocument.hashSource(exportedReader, filename: "out.heic")
        try exportedReader.close()
        XCTAssertEqual(exportedHash.sha256, expected.sha256)
        XCTAssertEqual(exportedHash.byteCount, UInt64(photoBytes))
        let photoReads = files.stats(for: photo)
        XCTAssertLessThanOrEqual(photoReads.maxRequest, StreamingBudget.chunkBytes)
        XCTAssertGreaterThan(photoReads.reads, 1)

        let againSize = try files.byteCount(at: archive)
        let again = try ShareCommit.commit(
            image,
            onto: reading,
            archive: archive,
            fileURL: photo,
            files: files,
            snapshots: .none
        )
        XCTAssertTrue(again.deduplicated)
        XCTAssertEqual(again.document.node(reading)?.attachments.count, 1)
        XCTAssertEqual(try files.byteCount(at: archive), againSize)
        XCTAssertEqual(again.directory.attachments.count, 1)

        let text = try ShareDraftBuilder.make(origin: .safari, text: "摘录")
        let withChild = try ShareCommit.commit(text, onto: center, archive: archive, files: files, snapshots: .none)
        let quote = try XCTUnwrap(withChild.childID)
        let beforeSecondNode = try files.byteCount(at: archive)
        let onChild = try ShareCommit.commit(
            image,
            onto: quote,
            archive: archive,
            fileURL: photo,
            files: files,
            snapshots: .none
        )
        XCTAssertTrue(onChild.deduplicated)
        XCTAssertEqual(onChild.directory.attachments.count, 1)
        XCTAssertEqual(onChild.document.node(quote)?.attachments.map(\.sha256), [expected.sha256])
        let growth = try files.byteCount(at: archive) - beforeSecondNode
        XCTAssertLessThan(growth, Int64(photoBytes))
    }

    func testUnknownNodeDoesNotWriteAndAFreeTopicKeepsThePageOnItself() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("map.floretta")
        var document = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "中心")]
        )
        let free = document.addFreeNode(text: "角落", at: MindMapPoint(x: 4, y: 8))
        let files = ShareProbeFiles()
        _ = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, snapshots: .none)
        let before = try files.byteCount(at: archive)
        let page = try ShareDraftBuilder.make(origin: .safari, url: "https://example.com/a", title: "文章")
        XCTAssertThrowsError(try ShareCommit.commit(
            page,
            onto: UUID(),
            archive: archive,
            files: files,
            snapshots: .none
        )) { error in
            XCTAssertEqual(error as? ShareIngressError, .unknownNode)
        }
        XCTAssertEqual(try files.byteCount(at: archive), before)

        let stored = try ShareCommit.commit(page, onto: free, archive: archive, files: files, snapshots: .none)
        let node = try XCTUnwrap(stored.document.node(free))
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.link, "https://example.com/a")
        XCTAssertEqual(node.note, "文章")
        XCTAssertTrue(stored.storedOnNode)
        XCTAssertNil(stored.childID)
    }

    func testNamingATopicByPathUUIDOrTitle() throws {
        let center = UUID()
        let reading = UUID()
        let other = UUID()
        let document = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: center, text: "中心", children: [
                MindMapNode(id: reading, text: "阅读"),
                MindMapNode(id: other, text: "阅读"),
            ])]
        )
        let topics = ShareIngress.topics(in: document)
        XCTAssertEqual(topics.map(\.path), ["中心", "中心 / 阅读", "中心 / 阅读"])
        XCTAssertEqual(topics.map(\.depth), [0, 1, 1])
        XCTAssertTrue(topics.allSatisfy(\.acceptsChild))
        XCTAssertEqual(ShareIngress.match(reading.uuidString, in: document), .found(reading))
        XCTAssertEqual(ShareIngress.match("中心 / 阅读", in: document), .ambiguous)
        XCTAssertEqual(ShareIngress.match("阅读", in: document), .ambiguous)
        XCTAssertEqual(ShareIngress.match("中心", in: document), .found(center))
        XCTAssertEqual(ShareIngress.match("中心／阅读", in: document), .ambiguous)
        XCTAssertEqual(ShareIngress.match("没有", in: document), .none)
        XCTAssertEqual(ShareIngress.match("  \(center.uuidString)  ", in: document), .found(center))

        let unique = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: center, text: "中心", children: [
                MindMapNode(id: reading, text: "阅读"),
            ])]
        )
        XCTAssertEqual(ShareIngress.match("中心 / 阅读", in: unique), .found(reading))
        XCTAssertEqual(ShareIngress.match("阅读", in: unique), .found(reading))
    }

    func testLoadPlanPrefersThePageAndTheConcreteImageType() throws {
        XCTAssertEqual(
            ShareTypeChoice.plan(registeredTypeIdentifiers: [["public.url", "public.image", "public.jpeg"]]),
            .webPage
        )
        XCTAssertEqual(
            ShareTypeChoice.plan(registeredTypeIdentifiers: [["public.image"], ["public.heic"]]),
            .file(typeIdentifier: "public.heic")
        )
        XCTAssertEqual(
            ShareTypeChoice.plan(registeredTypeIdentifiers: [["public.plain-text"]]),
            .plainText
        )
        XCTAssertEqual(ShareTypeChoice.filename(suggested: "IMG_1.HEIC", typeIdentifier: "public.heic"), "IMG_1.HEIC")
        XCTAssertEqual(ShareTypeChoice.filename(suggested: "照片", typeIdentifier: "public.png"), "照片.png")
        XCTAssertEqual(ShareTypeChoice.filename(suggested: nil, typeIdentifier: "public.jpeg"), "图片.jpg")

        let safari = try ShareDraftBuilder.make(
            origin: .safari,
            url: "https://example.com/x",
            title: "标题",
            file: ShareFileFact(filename: "preview.jpg", byteCount: 4, isDirectory: false)
        )
        XCTAssertEqual(safari.origin, .safari)
        if case .webPage = safari.kind {} else { XCTFail("Safari must keep the page") }

        XCTAssertThrowsError(try ShareDraftBuilder.make(
            origin: .photos,
            file: ShareFileFact(filename: "Album", byteCount: 1, isDirectory: true)
        )) { error in
            XCTAssertEqual(error as? ShareIngressError, .directory)
        }
        XCTAssertThrowsError(try ShareDraftBuilder.make(origin: .shortcuts, text: "   ")) { error in
            XCTAssertEqual(error as? ShareIngressError, .emptyPayload)
        }
        let huge = String(repeating: "字", count: ShareTopicText.maxUTF8Bytes + 1)
        XCTAssertThrowsError(try ShareDraftBuilder.make(origin: .shortcuts, text: huge)) { error in
            XCTAssertEqual(error as? ShareIngressError, .textTooLarge)
        }
        let shortcut = try ShareDraftBuilder.make(
            origin: .shortcuts,
            url: "https://example.com/x",
            text: "说明",
            file: ShareFileFact(filename: "shot.png", byteCount: 8, isDirectory: false)
        )
        XCTAssertEqual(shortcut.kind, .file(filename: "shot.png", byteCount: 8))

        let over = ShareIngress.proposal(
            for: try ShareDraftBuilder.make(
                origin: .photos,
                file: ShareFileFact(filename: "huge.heic", byteCount: StreamingBudget.softCapBytes + 1, isDirectory: false)
            ),
            currentDocumentByteCount: 0
        )
        XCTAssertEqual(over?.exceedsSoftCap, true)
        XCTAssertTrue(over?.confirmationMessage.contains("超过 10GB 软上限。") == true)
        XCTAssertNil(ShareLinks.webURL("file:///tmp/a.png"))
        XCTAssertEqual(ShareLinks.webURL("https://example.com/a"), "https://example.com/a")
        XCTAssertEqual(ShareTopicText.webTitle(url: "https://example.com/a", title: "  "), "example.com")
    }

    func testOpenEditorKeepsUnsavedTopicsWhenAShortcutWrites() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("map.floretta")
        let center = UUID()
        let document = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: center, text: "中心")]
        )
        let files = ShareProbeFiles()
        _ = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, snapshots: .none)
        var memory = document
        let unsaved = UUID()
        XCTAssertTrue(memory.insertChild(MindMapNode(id: unsaved, text: "还没保存"), under: center))
        let page = try ShareDraftBuilder.make(origin: .shortcuts, url: "https://example.com/s", title: "链")
        let saved = try ShareCommit.commit(
            page,
            onto: center,
            archive: archive,
            files: files,
            memory: memory,
            snapshots: .none
        )
        let texts = saved.document.node(center)?.children.map(\.text) ?? []
        XCTAssertEqual(texts, ["还没保存", "链"])
        let reader = try files.openReader(at: archive)
        let opened = try FlorettaStreamingDocument.open(reader)
        try reader.close()
        XCTAssertEqual(opened.document.node(center)?.children.map(\.text), ["还没保存", "链"])
    }

    func testAbsorbKeepsLocalEditsAndPicksUpTheShare() {
        let center = UUID()
        let kept = UUID()
        let removed = UUID()
        let base = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(id: center, text: "中心", children: [
                MindMapNode(id: kept, text: "留下"),
                MindMapNode(id: removed, text: "删掉"),
            ])]
        )
        var mine = base
        XCTAssertTrue(mine.removeNode(removed))
        let local = UUID()
        XCTAssertTrue(mine.insertChild(MindMapNode(id: local, text: "本地"), under: center))
        mine.mutateNode(center) { $0.text = "中心改了" }
        let shared = UUID()
        var theirs = base
        theirs.modifiedAt = stamped.addingTimeInterval(30)
        XCTAssertTrue(theirs.insertChild(MindMapNode(id: shared, text: "分享", link: "https://example.com"), under: center))
        let hash = String(repeating: "a", count: 64)
        theirs.mutateNode(center) { node in
            node.attachments.append(NodeAttachment(sha256: hash, fileExtension: "png", byteCount: 12, filename: "a.png"))
        }

        let merged = ShareAbsorb.absorb(base: base, mine: mine, theirs: theirs)
        let root = merged.node(center)
        XCTAssertEqual(root?.text, "中心改了")
        XCTAssertEqual(root?.children.map(\.id), [kept, local, shared])
        XCTAssertEqual(root?.children.last?.link, "https://example.com")
        XCTAssertEqual(root?.attachments.map(\.sha256), [hash])
        XCTAssertNil(merged.node(removed))

        // Same package again. The baseline stays `theirs`, which still contains 「删掉」.
        let again = ShareAbsorb.absorb(base: theirs, mine: merged, theirs: theirs)
        XCTAssertEqual(again, merged)
        XCTAssertNil(again.node(removed))

        var later = theirs
        let newer = UUID()
        XCTAssertTrue(later.insertChild(MindMapNode(id: newer, text: "后又"), under: center))
        let third = ShareAbsorb.absorb(base: theirs, mine: again, theirs: later)
        XCTAssertEqual(third.node(center)?.children.map(\.id), [kept, local, shared, newer])
        XCTAssertNil(third.node(removed))
        XCTAssertEqual(ShareAbsorb.absorb(base: base, mine: mine, theirs: base).node(center)?.children.map(\.id), [kept, local])
    }

    func testCatalogKeepsTheNewestForty() {
        var catalog = ShareDocumentCatalog()
        for index in 0..<45 {
            catalog = catalog.upsert(ShareDocumentEntry(
                id: "path-\(index)",
                filename: "\(index).floretta",
                bookmark: Data([UInt8(index)]),
                topicCount: index
            ))
        }
        XCTAssertEqual(catalog.documents.count, ShareDocumentCatalog.maxDocuments)
        XCTAssertEqual(catalog.documents.first?.id, "path-44")
        XCTAssertFalse(catalog.documents.contains { $0.id == "path-0" })
        catalog = catalog.upsert(ShareDocumentEntry(
            id: "path-44",
            filename: "renamed.floretta",
            bookmark: Data([9]),
            topicCount: 3
        ))
        XCTAssertEqual(catalog.documents.first?.filename, "renamed.floretta")
        XCTAssertEqual(catalog.documents.filter { $0.id == "path-44" }.count, 1)
    }

    func testCommitRejectsAMissingPackage() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("missing.floretta")
        let files = ShareProbeFiles()
        let text = try ShareDraftBuilder.make(origin: .shortcuts, text: "你好")
        XCTAssertThrowsError(try ShareCommit.commit(
            text,
            onto: UUID(),
            archive: archive,
            files: files,
            snapshots: .none
        )) { error in
            XCTAssertEqual(error as? ShareIngressError, .notAPackage)
        }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floretta-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePattern(to url: URL, count: Int) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var block = [UInt8](repeating: 0, count: 64 * 1024)
        for index in block.indices {
            block[index] = UInt8(truncatingIfNeeded: index &* 17)
        }
        var left = count
        while left > 0 {
            let n = min(left, block.count)
            try handle.write(contentsOf: block.prefix(n))
            left -= n
        }
        try handle.close()
    }
}

private final class ShareProbeFiles: StreamingFilePort {
    private var probes: [String: Probe] = [:]

    func resetPhotoReads(_ url: URL) {
        probes[url.path] = Probe()
    }

    func stats(for url: URL) -> (maxRequest: Int, reads: Int) {
        let probe = probes[url.path] ?? Probe()
        return (probe.maxRequest, probe.reads)
    }

    func byteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isZip(at url: URL) throws -> Bool {
        let reader = try openReader(at: url)
        defer { try? reader.close() }
        var bytes = [UInt8](repeating: 0, count: 2)
        let count = try bytes.withUnsafeMutableBytes { try reader.read(at: 0, into: $0) }
        return count == 2 && bytes[0] == 0x50 && bytes[1] == 0x4B
    }

    func openReader(at url: URL) throws -> RandomAccessReader {
        let probe = probes[url.path] ?? Probe()
        probes[url.path] = probe
        return try ProbeReader(url, probe: probe)
    }

    func openWriter(at url: URL) throws -> SequentialByteWriter {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try ProbeWriter(url)
    }

    func makeTemporary(nextTo url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AtomicFileBytes.partialURL(for: url)
    }

    func replace(destination: URL, with temporary: URL) throws {
        try AtomicFileBytes.commit(temporary: temporary, replacing: destination)
    }

    func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private final class Probe {
    var maxRequest = 0
    var reads = 0
}

private final class ProbeReader: RandomAccessReader {
    let count: Int64
    private let handle: FileHandle
    private let probe: Probe

    init(_ url: URL, probe: Probe) throws {
        handle = try FileHandle(forReadingFrom: url)
        count = Int64(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        self.probe = probe
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        probe.maxRequest = max(probe.maxRequest, buffer.count)
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        let data = try handle.read(upToCount: buffer.count) ?? Data()
        if data.count > 0 {
            probe.reads += 1
            data.withUnsafeBytes { raw in
                guard let source = raw.baseAddress else { return }
                base.copyMemory(from: source, byteCount: data.count)
            }
        }
        return data.count
    }

    func close() throws {
        try handle.close()
    }
}

private final class ProbeWriter: SequentialByteWriter {
    private let handle: FileHandle

    init(_ url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard buffer.count > 0 else { return }
        try handle.write(contentsOf: Data(buffer))
    }

    func synchronize() throws {
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}
