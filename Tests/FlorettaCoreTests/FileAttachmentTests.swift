import FlorettaCore
import XCTest

final class FileAttachmentTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testAnyFileIsAcceptedAndImagesStayOnTheImageRoute() {
        for name in ["Poster.psd", "Notes.PDF", "Floretta.dmg", "archive.bin", "noextension"] {
            XCTAssertTrue(FileAttachmentRoute.accepts(filename: name), name)
            XCTAssertNotNil(FileAttachmentRoute.proposal(filename: name, byteCount: 8, currentDocumentByteCount: 1))
        }
        XCTAssertFalse(FileAttachmentRoute.accepts(filename: "Folder", isDirectory: true))
        XCTAssertNil(FileAttachmentRoute.proposal(filename: "Folder", byteCount: 8, currentDocumentByteCount: 0, isDirectory: true))
        XCTAssertFalse(FileAttachmentRoute.accepts(filename: " "))
        XCTAssertFalse(ImageInsertRoute.accepts(filename: "Poster.psd"))
        XCTAssertFalse(ImageInsertRoute.accepts(filename: "Notes.PDF"))
        XCTAssertFalse(ImageInsertRoute.accepts(filename: "Floretta.dmg"))
        XCTAssertTrue(ImageInsertRoute.accepts(filename: "shot.png"))
    }

    func testConfirmDialogShowsFileSizeAndProjectedTotal() {
        let names = ["Poster.psd", "Notes.PDF", "Floretta.dmg"]
        for name in names {
            let proposal = FileAttachmentRoute.proposal(
                filename: name,
                byteCount: 2048,
                currentDocumentByteCount: 1024
            )
            let direct = AttachmentInsertProposal(
                filename: name,
                fileByteCount: 2048,
                currentDocumentByteCount: 1024
            )
            XCTAssertEqual(proposal, direct, name)
            XCTAssertEqual(proposal?.fileByteCount, 2048)
            XCTAssertEqual(proposal?.projectedDocumentByteCount, 3072)
            XCTAssertTrue(proposal?.confirmationMessage.contains("文件大小：2.0 KB") == true, name)
            XCTAssertTrue(proposal?.confirmationMessage.contains("放入后文档大约：3.0 KB") == true, name)
            XCTAssertTrue(proposal?.confirmationMessage.contains("不压缩、不转码") == true, name)
        }
        let huge = FileAttachmentRoute.proposal(
            filename: "big.psd",
            byteCount: StreamingBudget.softCapBytes + 1,
            currentDocumentByteCount: 0
        )
        XCTAssertEqual(huge?.exceedsSoftCap, true)
        XCTAssertTrue(huge?.confirmationMessage.contains("超过 10GB 软上限。") == true)
    }

    func testStoredNameKeepsTheExtensionUTTypeRecognized() {
        XCTAssertEqual(FileAttachmentName.storedFilename(original: "Poster.psd", recognizedExtension: "psd"), "Poster.psd")
        XCTAssertEqual(FileAttachmentName.storedFilename(original: "Notes.PDF", recognizedExtension: "bin"), "Notes.PDF")
        XCTAssertEqual(FileAttachmentName.storedFilename(original: "download", recognizedExtension: "pdf"), "download.pdf")
        XCTAssertEqual(FileAttachmentName.storedFilename(original: "blob", recognizedExtension: "bin"), "blob")
    }

    func testIconFallsBackWhenTheSystemHasNoIcon() {
        let pdf = FileTypeFact(typeIdentifier: "com.adobe.pdf", systemIconAvailable: true, fileExtension: "pdf")
        XCTAssertEqual(FileIconPolicy.resolution(for: pdf), .system(typeIdentifier: "com.adobe.pdf"))

        let psd = FileTypeFact(typeIdentifier: "com.adobe.photoshop-image", systemIconAvailable: false, fileExtension: "psd")
        XCTAssertEqual(FileIconPolicy.resolution(for: psd), .generic(typeIdentifier: "com.adobe.photoshop-image"))

        let dyn = FileTypeFact(typeIdentifier: "dyn.ah62d4", systemIconAvailable: true, fileExtension: "qzxfloretta")
        XCTAssertEqual(FileIconPolicy.resolution(for: dyn), .generic(typeIdentifier: "dyn.ah62d4"))

        let unknown = FileTypeFact(typeIdentifier: nil, systemIconAvailable: false, fileExtension: "bin")
        XCTAssertEqual(FileIconPolicy.resolution(for: unknown), .generic(typeIdentifier: nil))
    }

    func testNodeBadgeShowsIconFilenameAndSizeWithoutTouchingPictures() throws {
        let pdfHash = String(repeating: "a", count: 64)
        let pngHash = String(repeating: "b", count: 64)
        let dmgHash = String(repeating: "c", count: 64)
        let psdHash = String(repeating: "d", count: 64)
        let mixed = MindMapDocument(
            title: "混合",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "主题", attachments: [
                NodeAttachment(sha256: pdfHash, fileExtension: "pdf", byteCount: 4, filename: "notes.pdf"),
                NodeAttachment(sha256: pngHash, fileExtension: "png", byteCount: 8, filename: "pic.png"),
            ])]
        )
        let files = MindMapDocument(
            title: "文件",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "主题", attachments: [
                NodeAttachment(sha256: dmgHash, fileExtension: "dmg", byteCount: 2048, filename: "Floretta.dmg"),
                NodeAttachment(sha256: psdHash, fileExtension: "psd", byteCount: 4096, filename: "Poster.psd"),
            ])]
        )
        let picture = MindMapDocument(
            title: "图",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "主题", attachments: [
                NodeAttachment(sha256: pngHash, fileExtension: "png", byteCount: 8, filename: "pic.png"),
            ])]
        )
        let plain = MindMapDocument(title: "空", createdAt: stamped, modifiedAt: stamped, roots: [MindMapNode(text: "主题")])

        let mixedFrame = try XCTUnwrap(LayoutEngine().layout(mixed).first)
        let fileFrame = try XCTUnwrap(LayoutEngine().layout(files).first)
        let pictureFrame = try XCTUnwrap(LayoutEngine().layout(picture).first)
        let plainFrame = try XCTUnwrap(LayoutEngine().layout(plain).first)

        XCTAssertEqual(pictureFrame.fileBadges.count, 0)
        XCTAssertEqual(pictureFrame.thumbnailHashes, [pngHash])
        XCTAssertEqual(plainFrame.fileBadges.count, 0)
        XCTAssertGreaterThan(pictureFrame.size.height, plainFrame.size.height)

        XCTAssertEqual(mixedFrame.thumbnailHashes, [pngHash])
        XCTAssertEqual(mixedFrame.fileBadges.map(\.filename), ["notes.pdf"])
        XCTAssertEqual(mixedFrame.fileBadges.map(\.sizeLabel), [AttachmentByteFormat.label(4)])
        XCTAssertTrue(mixedFrame.caption.contains("notes.pdf"))
        XCTAssertTrue(mixedFrame.caption.contains(AttachmentByteFormat.label(4)))
        XCTAssertEqual(
            NodeAttachmentDrawing.canvasText(title: mixedFrame.text, caption: mixedFrame.caption, fileBadges: mixedFrame.fileBadges),
            "主题\npic.png \(AttachmentByteFormat.label(8))"
        )
        XCTAssertEqual(NodeAttachmentDrawing.measuredText(mixed.roots[0]), "主题\npic.png \(AttachmentByteFormat.label(8))")

        XCTAssertEqual(fileFrame.fileBadges.map(\.fileExtension), ["dmg", "psd"])
        XCTAssertEqual(fileFrame.fileBadges.map(\.filename), ["Floretta.dmg", "Poster.psd"])
        XCTAssertEqual(fileFrame.fileBadges.map(\.sizeLabel), [AttachmentByteFormat.label(2048), AttachmentByteFormat.label(4096)])
        XCTAssertTrue(fileFrame.thumbnailHashes.isEmpty)
        XCTAssertGreaterThanOrEqual(fileFrame.size.height - plainFrame.size.height, FileBadgeMetrics.bandHeight(count: 2))
        XCTAssertEqual(
            NodeAttachmentDrawing.canvasText(title: fileFrame.text, caption: fileFrame.caption, fileBadges: fileFrame.fileBadges),
            "主题"
        )

        let badge = try XCTUnwrap(fileFrame.fileBadges.first)
        XCTAssertGreaterThan(badge.icon.width, 0)
        XCTAssertGreaterThan(badge.icon.height, 0)
        XCTAssertLessThanOrEqual(badge.icon.x + badge.icon.width, badge.row.x + badge.row.width + 0.001)
        XCTAssertLessThanOrEqual(badge.row.y + badge.row.height, Double(fileFrame.size.height) + 0.001)
        XCTAssertGreaterThan(badge.row.y, 4)
        let hit = FileBadgeHit.badge(
            canvasX: Double(fileFrame.origin.x) + badge.icon.x + 1,
            canvasY: Double(fileFrame.origin.y) + badge.icon.y + 1,
            in: fileFrame
        )
        XCTAssertEqual(hit?.sha256, dmgHash)
        XCTAssertNil(FileBadgeHit.badge(
            canvasX: Double(fileFrame.origin.x) + 2,
            canvasY: Double(fileFrame.origin.y) + 2,
            in: fileFrame
        ))
    }

    func testPreviewClosesWithAnAlertWhenTheFileDisappears() {
        let ticket = FilePreviewTicket(
            nodeID: UUID(),
            sha256: String(repeating: "e", count: 64),
            filename: "notes.pdf",
            previewPath: "/tmp/floretta-notes.pdf"
        )
        XCTAssertEqual(FilePreviewSession.begin(ticket, fileExists: false).alertMessage, FilePreviewSession.missingMessage)
        let showing = FilePreviewSession.begin(ticket, fileExists: true)
        XCTAssertEqual(showing.previewPath, ticket.previewPath)
        XCTAssertEqual(FilePreviewSession.fileDisappeared(showing), .alert(FilePreviewSession.missingMessage))
        XCTAssertEqual(FilePreviewSession.fileDisappeared(.idle), .idle)
        XCTAssertEqual(FilePreviewSession.fileDisappeared(.alert("保留")), .alert("保留"))
        XCTAssertEqual(FilePreviewSession.userClosed(showing), .idle)
        XCTAssertEqual(FilePreviewSession.userClosed(.alert(FilePreviewSession.missingMessage)).alertMessage, FilePreviewSession.missingMessage)
        XCTAssertEqual(FilePreviewSession.dismissAlert(.alert(FilePreviewSession.missingMessage)), .idle)
        XCTAssertEqual(FilePreviewSession.unavailable().alertMessage, FilePreviewSession.unavailableMessage)
        XCTAssertFalse(FilePreviewSession.missingMessage.isEmpty)
    }

    func testSpillIsByteIdenticalAndDedupedForPSDPdfAndDMG() throws {
        let directory = try makeDirectory()
        let files = HandleFiles()
        let psd = Data([0x38, 0x42, 0x50, 0x53, 0x00, 0xFF])
        let pdf = Data("%PDF-1.4 floretta".utf8)
        let dmg = Data(repeating: 0xAB, count: 48)
        let psdURL = directory.appendingPathComponent("Poster.psd")
        let pdfURL = directory.appendingPathComponent("Notes.PDF")
        let dmgURL = directory.appendingPathComponent("Floretta.dmg")
        let psdAgain = directory.appendingPathComponent("Copy.psd")
        try psd.write(to: psdURL)
        try pdf.write(to: pdfURL)
        try dmg.write(to: dmgURL)
        try psd.write(to: psdAgain)

        var document = MindMapDocument(title: "附件", createdAt: stamped, modifiedAt: stamped, roots: [
            MindMapNode(text: "根"),
        ])
        let archive = directory.appendingPathComponent("map.floretta")
        let psdHash = try hashed(psdURL, files: files)
        let pdfHash = try hashed(pdfURL, files: files)
        let dmgHash = try hashed(dmgURL, files: files)
        let copyHash = try hashed(psdAgain, files: files)
        XCTAssertEqual(psdHash.sha256, copyHash.sha256)
        XCTAssertNotEqual(psdHash.sha256, pdfHash.sha256)

        document.roots[0].attachments = [
            try psdHash.nodeAttachment(),
            try pdfHash.nodeAttachment(),
            try dmgHash.nodeAttachment(),
        ]
        let written = try FlorettaStreamingDocument.save(
            document: document,
            to: archive,
            files: files,
            appending: (psdURL, psdHash)
        )
        _ = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, appending: (pdfURL, pdfHash))
        let stored = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, appending: (dmgURL, dmgHash))
        XCTAssertEqual(stored.attachments.count, 3)
        XCTAssertTrue(stored.attachments.allSatisfy { $0.method == 0 })

        document.roots[0].children = [MindMapNode(text: "再", attachments: [try copyHash.nodeAttachment()])]
        let deduped = try FlorettaStreamingDocument.save(document: document, to: archive, files: files, appending: (psdAgain, copyHash))
        XCTAssertEqual(deduped.attachments.count, 3)
        XCTAssertEqual(AttachmentReferences.counts(in: document).first { $0.sha256 == psdHash.sha256 }?.count, 2)

        try assertSpill(psd, fileExtension: "psd", in: deduped, archive: archive, files: files, directory: directory)
        try assertSpill(pdf, fileExtension: "pdf", in: deduped, archive: archive, files: files, directory: directory)
        try assertSpill(dmg, fileExtension: "dmg", in: deduped, archive: archive, files: files, directory: directory)
        _ = written
    }

    func testCompressedAttachmentIsNotSpilled() throws {
        let entry = ZipStoredEntry(
            name: "assets/\(String(repeating: "a", count: 64)).psd",
            method: 8,
            crc32: 0,
            byteCount: 4,
            localHeaderOffset: 0,
            dataOffset: 0
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("floretta-compressed-\(UUID().uuidString).psd")
        XCTAssertThrowsError(
            try FilePreviewSpill.write(
                entry: entry,
                archiveURL: URL(fileURLWithPath: "/tmp/missing-floretta-archive"),
                to: destination,
                files: HandleFiles()
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func assertSpill(
        _ payload: Data,
        fileExtension ext: String,
        in directory: ZipDirectory,
        archive: URL,
        files: HandleFiles,
        directory folder: URL
    ) throws {
        let entry = try XCTUnwrap(directory.attachments.first {
            AttachmentNames.parseAsset($0.name)?.fileExtension == ext
        })
        XCTAssertEqual(entry.method, 0)
        let spilled = folder.appendingPathComponent("spill-\(ext)")
        try FilePreviewSpill.write(entry: entry, archiveURL: archive, to: spilled, files: files)
        XCTAssertEqual(try Data(contentsOf: spilled), payload)
    }

    private func hashed(_ url: URL, files: HandleFiles) throws -> HashedAttachment {
        let reader = try files.openReader(at: url)
        let hashed = try FlorettaStreamingDocument.hashSource(reader, filename: url.lastPathComponent)
        try reader.close()
        return hashed
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floretta-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class HandleFiles: StreamingFilePort {
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
        try SliceReader(url)
    }

    func openWriter(at url: URL) throws -> SequentialByteWriter {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try SliceWriter(url)
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

private final class SliceReader: RandomAccessReader {
    let count: Int64
    private let handle: FileHandle

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        count = Int64(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        let data = try handle.read(upToCount: buffer.count) ?? Data()
        data.withUnsafeBytes { raw in
            guard let source = raw.baseAddress, data.count > 0 else { return }
            base.copyMemory(from: source, byteCount: data.count)
        }
        return data.count
    }

    func close() throws {
        try handle.close()
    }
}

private final class SliceWriter: SequentialByteWriter {
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
