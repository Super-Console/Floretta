import FlorettaCore
import Foundation
import XCTest

final class SnapshotRecoveryTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
    }

    func testCommitIsFsyncThenRenameAndLeavesNoPartial() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        _ = try save(title: "第一", to: url, files: files)
        XCTAssertEqual(files.events, ["sync", "replace"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: AtomicFileBytes.partialURL(for: url).path))
        XCTAssertEqual(try openedTitle(url, files: files), "第一")
        XCTAssertEqual(try openedVersion(url, files: files), MindMapDocument.currentFormatVersion)
        XCTAssertEqual(MindMapDocument.currentFormatVersion, 1)

        let before = try Data(contentsOf: url)
        files.events.removeAll()
        files.failAfterBytes = 24
        XCTAssertThrowsError(try save(title: "半截", to: url, files: files))
        XCTAssertFalse(files.events.contains("replace"))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: AtomicFileBytes.partialURL(for: url).path))
        XCTAssertThrowsError(try AtomicFileBytes.commit(temporary: directory.appendingPathComponent("missing"), replacing: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testPowerLossLeavesThePartialAndRestoreKeepsThePreviousFile() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        _ = try save(title: "上一版", to: url, files: files)
        let intact = try Data(contentsOf: url)
        try Data("half-written-zip".utf8).write(to: AtomicFileBytes.partialURL(for: url))

        let found = try XCTUnwrap(SaveRecovery.inspect(documentAt: url, files: files))
        XCTAssertTrue(found.canRestorePrevious)
        XCTAssertEqual(found.promptTitle, "保存未完成")
        XCTAssertTrue(found.promptMessage.contains("上一个完整版本"))
        XCTAssertEqual(found.partialURL.lastPathComponent, AtomicFileBytes.partialURL(for: url).lastPathComponent)

        let restored = try SaveRecovery.restorePrevious(documentAt: url, files: files)
        XCTAssertEqual(restored.title, "上一版")
        XCTAssertEqual(try Data(contentsOf: url), intact)
        XCTAssertFalse(FileManager.default.fileExists(atPath: found.partialURL.path))
        XCTAssertNil(SaveRecovery.inspect(documentAt: url, files: files))
    }

    func testPowerLossWithADamagedFileRestoresTheSnapshot() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        let photo = directory.appendingPathComponent("照片.png")
        try Data("png-bytes".utf8).write(to: photo)
        _ = try save(title: "带图", to: url, files: files, attachment: photo)
        _ = try save(title: "第二版", to: url, files: files, attachment: photo)
        try Data("NOT-A-ZIP".utf8).write(to: url)
        try Data("torn".utf8).write(to: AtomicFileBytes.partialURL(for: url))

        let found = try XCTUnwrap(SaveRecovery.inspect(documentAt: url, files: files))
        XCTAssertTrue(found.canRestorePrevious)
        XCTAssertTrue(found.promptMessage.contains("快照"))
        let restored = try SaveRecovery.restorePrevious(documentAt: url, files: files)
        XCTAssertEqual(restored.title, "带图")
        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        XCTAssertEqual(opened.document.title, "带图")
        XCTAssertEqual(opened.document.formatVersion, 1)
        XCTAssertThrowsError(try FlorettaStreamingDocument.verifyInventory(reader, opened: opened)) { error in
            guard let inventory = error as? AssetInventoryError else {
                return XCTFail("expected AssetInventoryError, got \(error)")
            }
            XCTAssertEqual(inventory.promptTitle, "附件已损坏")
            XCTAssertTrue(inventory.promptMessage.contains("照片.png"))
            XCTAssertTrue(inventory.promptMessage.contains("不是整份导图读失败"))
            XCTAssertFalse(inventory.promptMessage.contains("document.json could not be read"))
        }
        try reader.close()
    }

    func testPowerLossWithNothingToRestoreSaysSo() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        try Data("torn".utf8).write(to: AtomicFileBytes.partialURL(for: url))
        let found = try XCTUnwrap(SaveRecovery.inspect(documentAt: url, files: files))
        XCTAssertFalse(found.canRestorePrevious)
        XCTAssertTrue(found.promptMessage.contains("没有可恢复的上一版"))
        XCTAssertThrowsError(try SaveRecovery.restorePrevious(documentAt: url, files: files)) { _ in }
        try SaveRecovery.discardPartial(documentAt: url, files: files)
        XCTAssertFalse(FileManager.default.fileExists(atPath: found.partialURL.path))
        XCTAssertNil(SaveRecovery.inspect(documentAt: url, files: files))
    }

    func testSnapshotsAreCappedAndRollbackRestoresDocumentJSON() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        XCTAssertEqual(SnapshotRetention(limit: 100).limit, SnapshotRetention.hardCap)
        XCTAssertEqual(SnapshotRetention.none.limit, 0)
        _ = try save(title: "第一", to: url, files: files, snapshots: SnapshotRetention(limit: 2))
        _ = try save(title: "第二", to: url, files: files, snapshots: SnapshotRetention(limit: 2))
        _ = try save(title: "第三", to: url, files: files, snapshots: SnapshotRetention(limit: 2))
        _ = try save(title: "第四", to: url, files: files, snapshots: SnapshotRetention(limit: 2))
        let listed = try DocumentSnapshots.list(documentAt: url)
        XCTAssertEqual(listed.map(\.document.title), ["第二", "第三"])
        XCTAssertEqual(try openedVersion(url, files: files), 1)

        let rolled = try DocumentSnapshots.rollback(documentAt: url, to: listed[0].generation, files: files, retention: SnapshotRetention(limit: 2))
        XCTAssertEqual(rolled.title, "第二")
        XCTAssertEqual(try openedTitle(url, files: files), "第二")
        let after = try DocumentSnapshots.list(documentAt: url)
        XCTAssertTrue(after.map(\.document.title).contains("第四"))

        let folder = DocumentSnapshots.directory(for: url)
        try FileManager.default.removeItem(at: folder)
        XCTAssertEqual(try openedTitle(url, files: files), "第二")
        XCTAssertEqual(try DocumentSnapshots.list(documentAt: url).count, 0)
    }

    func testHardCapStopsAtThirtyTwoCopies() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        for index in 1...34 {
            _ = try save(title: "v\(index)", to: url, files: files, snapshots: SnapshotRetention(limit: 100))
        }
        let listed = try DocumentSnapshots.list(documentAt: url)
        XCTAssertEqual(listed.count, SnapshotRetention.hardCap)
        XCTAssertEqual(listed.first?.document.title, "v2")
        XCTAssertEqual(listed.last?.document.title, "v33")
    }

    func testSnapshotPinsAttachmentBytesUntilItAgesOut() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        let photo = directory.appendingPathComponent("a.bin")
        try Data("aaaa".utf8).write(to: photo)
        _ = try save(title: "有图", to: url, files: files, snapshots: SnapshotRetention(limit: 1), attachment: photo)
        let kept = try save(title: "无图", to: url, files: files, snapshots: SnapshotRetention(limit: 1))
        XCTAssertEqual(kept.attachments.count, 1)
        let dropped = try save(title: "仍无图", to: url, files: files, snapshots: SnapshotRetention(limit: 1))
        XCTAssertEqual(dropped.attachments.count, 0)
    }

    func testIdenticalSaveDoesNotGrowTheSnapshotList() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        let document = sample(title: "同一")
        try FlorettaStreamingDocument.save(document: document, to: url, files: files)
        try FlorettaStreamingDocument.save(document: document, to: url, files: files)
        try FlorettaStreamingDocument.save(document: document, to: url, files: files)
        XCTAssertEqual(try DocumentSnapshots.list(documentAt: url).count, 1)
    }

    func testCorruptAttachmentIsNamedAndTheDocumentJSONStillOpens() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        let photo = directory.appendingPathComponent("照片.png")
        let note = directory.appendingPathComponent("笔记.pdf")
        try Data("png-bytes-photo".utf8).write(to: photo)
        try Data("pdf-bytes-note".utf8).write(to: note)
        var document = sample(title: "两份")
        let photoHash = try hash(photo, files: files)
        let noteHash = try hash(note, files: files)
        document.roots[0].attachments = [try photoHash.nodeAttachment(), try noteHash.nodeAttachment()]
        _ = try FlorettaStreamingDocument.save(document: document, to: url, files: files, appending: (photo, photoHash), snapshots: .none)
        let written = try FlorettaStreamingDocument.save(document: document, to: url, files: files, appending: (note, noteHash), snapshots: .none)
        let photoEntry = try XCTUnwrap(written.attachments.first { $0.sha256 == photoHash.sha256 })
        var bytes = try Data(contentsOf: url)
        let index = Int(photoEntry.dataOffset)
        bytes[index] ^= 0xFF
        try bytes.write(to: url)

        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        XCTAssertEqual(opened.document.title, "两份")
        XCTAssertEqual(opened.document.formatVersion, 1)
        XCTAssertThrowsError(try FlorettaStreamingDocument.verifyInventory(reader, opened: opened)) { error in
            guard let inventory = error as? AssetInventoryError else {
                return XCTFail("expected AssetInventoryError, got \(error)")
            }
            XCTAssertEqual(inventory.failures.count, 1)
            XCTAssertEqual(inventory.failures[0].filename, "照片.png")
            XCTAssertEqual(inventory.failures[0].sha256, photoHash.sha256)
            XCTAssertTrue(inventory.failures[0].entryName.contains(photoHash.sha256))
            XCTAssertFalse(inventory.promptMessage.contains("笔记.pdf"))
            XCTAssertFalse(inventory.promptMessage.contains("document.json"))
            guard case .hashMismatch = inventory.failures[0].reason else {
                return XCTFail("expected a hash mismatch, got \(inventory.failures[0].reason)")
            }
        }
        try reader.close()

        XCTAssertThrowsError(try ZipContainer().read(data: bytes)) { error in
            guard let inventory = error as? AssetInventoryError else {
                return XCTFail("expected AssetInventoryError, got \(error)")
            }
            XCTAssertTrue(inventory.promptMessage.contains(photoHash.sha256))
            XCTAssertEqual(inventory.failures.first?.reason, .declaredChecksumMismatch)
            XCTAssertTrue(inventory.promptMessage.contains("不是整份导图读失败"))
            XCTAssertFalse(inventory.promptMessage.contains("document.json"))
        }
    }

    func testMissingAttachmentIsNamedWithoutFailingTheWholeDocument() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        let files = RecordingFiles()
        var document = sample(title: "缺图")
        document.roots[0].attachments = [
            NodeAttachment(
                sha256: String(repeating: "ab", count: 32),
                fileExtension: "png",
                byteCount: 4,
                filename: "照片.png"
            ),
        ]
        _ = try FlorettaStreamingDocument.save(document: document, to: url, files: files, snapshots: .none)
        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        XCTAssertEqual(opened.document.roots[0].text, "根")
        XCTAssertThrowsError(try FlorettaStreamingDocument.verifyInventory(reader, opened: opened)) { error in
            guard let inventory = error as? AssetInventoryError else {
                return XCTFail("expected AssetInventoryError, got \(error)")
            }
            XCTAssertEqual(inventory.failures.count, 1)
            XCTAssertEqual(inventory.failures[0].filename, "照片.png")
            XCTAssertEqual(inventory.failures[0].reason, .missingFromPackage)
            XCTAssertTrue(inventory.promptMessage.contains("assets/\(String(repeating: "ab", count: 32)).png"))
            XCTAssertFalse(inventory.promptMessage.contains("document.json could not be read"))
        }
        try reader.close()
    }

    private func save(
        title: String,
        to url: URL,
        files: RecordingFiles,
        snapshots: SnapshotRetention = .standard,
        attachment: URL? = nil
    ) throws -> ZipDirectory {
        var document = sample(title: title)
        let appending: (url: URL, hashed: HashedAttachment)?
        if let attachment {
            let hashed = try hash(attachment, files: files)
            document.roots[0].attachments = [try hashed.nodeAttachment()]
            appending = (attachment, hashed)
        } else {
            appending = nil
        }
        return try FlorettaStreamingDocument.save(
            document: document,
            to: url,
            files: files,
            appending: appending,
            snapshots: snapshots
        )
    }

    private func hash(_ url: URL, files: RecordingFiles) throws -> HashedAttachment {
        let reader = try files.openReader(at: url)
        let hashed = try FlorettaStreamingDocument.hashSource(reader, filename: url.lastPathComponent)
        try reader.close()
        return hashed
    }

    private func openedTitle(_ url: URL, files: RecordingFiles) throws -> String {
        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        try reader.close()
        return opened.document.title
    }

    private func openedVersion(_ url: URL, files: RecordingFiles) throws -> Int {
        let reader = try files.openReader(at: url)
        let opened = try FlorettaStreamingDocument.open(reader)
        try reader.close()
        return opened.document.formatVersion
    }

    private func sample(title: String) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "根")]
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaSnapshotTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory
    }
}

private final class RecordingFiles: StreamingFilePort {
    var events: [String] = []
    var failAfterBytes: Int?

    func byteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isZip(at url: URL) throws -> Bool {
        guard fileExists(at: url) else { return false }
        let reader = try openReader(at: url)
        defer { try? reader.close() }
        var bytes = [UInt8](repeating: 0, count: 2)
        let count = try bytes.withUnsafeMutableBytes { try reader.read(at: 0, into: $0) }
        return count == 2 && bytes[0] == 0x50 && bytes[1] == 0x4B
    }

    func openReader(at url: URL) throws -> RandomAccessReader {
        try HandleReader(url)
    }

    func openWriter(at url: URL) throws -> SequentialByteWriter {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        return try HandleWriter(url, files: self)
    }

    func makeTemporary(nextTo url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AtomicFileBytes.partialURL(for: url)
    }

    func replace(destination: URL, with temporary: URL) throws {
        events.append("replace")
        try AtomicFileBytes.commit(temporary: temporary, replacing: destination)
    }

    func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private final class HandleReader: RandomAccessReader {
    let count: Int64
    private let handle: FileHandle

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        count = Int64(try handle.seekToEnd())
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

private final class HandleWriter: SequentialByteWriter {
    private let handle: FileHandle
    private let files: RecordingFiles
    private var written = 0

    init(_ url: URL, files: RecordingFiles) throws {
        handle = try FileHandle(forWritingTo: url)
        self.files = files
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard buffer.count > 0 else { return }
        if let limit = files.failAfterBytes, written + buffer.count > limit {
            throw CocoaError(.fileWriteUnknown)
        }
        written += buffer.count
        try handle.write(contentsOf: Data(buffer))
    }

    func synchronize() throws {
        files.events.append("sync")
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}
