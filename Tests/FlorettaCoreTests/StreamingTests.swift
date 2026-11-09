import FlorettaCore
import Foundation
import XCTest

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class StreamingTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testBudgetsMatchThePerformanceCeiling() {
        XCTAssertEqual(StreamingBudget.softCapBytes, 10 * 1024 * 1024 * 1024)
        XCTAssertEqual(StreamingBudget.writePeakBytes, 32 * 1024 * 1024)
        XCTAssertEqual(StreamingBudget.openRamDeltaBytes, 50 * 1024 * 1024)
        XCTAssertEqual(StreamingBudget.thumbnailCacheBytes, 200 * 1024 * 1024)
        XCTAssertLessThan(StreamingBudget.chunkBytes * 4, StreamingBudget.writePeakBytes)
    }

    func testProposalUsesSizesOnly() {
        let proposal = AttachmentInsertProposal(
            filename: "clip.MP4",
            fileByteCount: 1536,
            currentDocumentByteCount: 2048
        )
        XCTAssertEqual(proposal.fileExtension, "mp4")
        XCTAssertEqual(proposal.projectedDocumentByteCount, 3584)
        XCTAssertFalse(proposal.exceedsSoftCap)
        XCTAssertTrue(proposal.confirmationMessage.contains("文件大小：1.5 KB"))
        XCTAssertTrue(proposal.confirmationMessage.contains("放入后文档大约：3.5 KB"))
        XCTAssertTrue(proposal.confirmationMessage.contains("不压缩、不转码"))
        XCTAssertFalse(proposal.confirmationMessage.contains("软上限"))

        let over = AttachmentInsertProposal(
            filename: "huge.bin",
            fileByteCount: StreamingBudget.softCapBytes + 1,
            currentDocumentByteCount: 10
        )
        XCTAssertTrue(over.exceedsSoftCap)
        XCTAssertTrue(over.confirmationMessage.contains("超过 10GB 软上限。"))
    }

    func testStreamingRoundTripIsByteIdenticalAndDeduped() throws {
        let directory = try makeDirectory()
        let source = directory.appendingPathComponent("photo.bin")
        let payload = Data("floretta-bytes-\u{00ff}\u{0000}end".utf8)
        try payload.write(to: source)
        let files = POSIXStreamingFiles()
        let hashed = try hash(source, files: files)
        XCTAssertEqual(hashed.byteCount, UInt64(payload.count))
        XCTAssertLessThanOrEqual(files.maxRead, StreamingBudget.chunkBytes)

        var document = sampleDocument(title: "图")
        let attachment = try hashed.nodeAttachment()
        document.roots[0].attachments.append(attachment)
        let archive = directory.appendingPathComponent("map.floretta")
        let written = try FlorettaStreamingDocument.save(
            document: document,
            to: archive,
            files: files,
            appending: (source, hashed)
        )
        XCTAssertEqual(written.attachments.count, 1)
        XCTAssertEqual(written.attachments[0].method, 0)
        XCTAssertLessThanOrEqual(files.maxRead, StreamingBudget.chunkBytes)

        let exported = directory.appendingPathComponent("out.bin")
        let reader = try files.openReader(at: archive)
        let writer = try files.openWriter(at: exported)
        try FlorettaStreamingDocument.exportAttachment(written.attachments[0], from: reader, to: writer)
        try writer.close()
        try reader.close()
        XCTAssertEqual(try Data(contentsOf: exported), payload)

        let loaded = try ZipContainer().read(data: try Data(contentsOf: archive))
        XCTAssertEqual(loaded.document.roots[0].attachments, [attachment])
        XCTAssertEqual(loaded.assets.count, 1)
        XCTAssertEqual(loaded.assets[0].data, payload)

        let again = try FlorettaStreamingDocument.save(
            document: document,
            to: archive,
            files: files,
            appending: (source, hashed)
        )
        XCTAssertEqual(again.attachments.count, 1)
        let opened = try openTracking(archive, files: files)
        XCTAssertEqual(opened.package.directory.attachments.count, 1)
        XCTAssertFalse(opened.touchedPayload)
        XCTAssertLessThan(opened.bytesRead, archiveByteCount(archive))
    }

    func testLargeInsertStaysUnderTheWriteCeiling() throws {
        let directory = try makeDirectory()
        let bytes: Int64 = 36 * 1024 * 1024
        let source = directory.appendingPathComponent("wide.bin")
        let head = Data("HEAD-MARK".utf8)
        let tail = Data("TAIL-MARK".utf8)
        try writeSparse(source, size: bytes, head: head, tail: tail)
        let files = POSIXStreamingFiles()
        let before = residentBytes()
        let hashed = try hash(source, files: files)
        var document = sampleDocument(title: "大")
        let attachment = try hashed.nodeAttachment()
        document.roots[0].attachments.append(attachment)
        let archive = directory.appendingPathComponent("map.floretta")
        let written = try FlorettaStreamingDocument.save(
            document: document,
            to: archive,
            files: files,
            appending: (source, hashed)
        )
        let after = residentBytes()
        XCTAssertLessThanOrEqual(files.maxRead, StreamingBudget.chunkBytes)
        XCTAssertGreaterThan(bytes, Int64(StreamingBudget.writePeakBytes))
        if before > 0, after > 0 {
            XCTAssertLessThan(after - before, Int64(StreamingBudget.writePeakBytes))
        }
        let exported = directory.appendingPathComponent("out.bin")
        let reader = try files.openReader(at: archive)
        let writer = try files.openWriter(at: exported)
        try FlorettaStreamingDocument.exportAttachment(written.attachments[0], from: reader, to: writer)
        try writer.close()
        try reader.close()
        XCTAssertEqual(archiveByteCount(exported), bytes)
        XCTAssertEqual(try readRange(exported, offset: 0, count: head.count), head)
        XCTAssertEqual(try readRange(exported, offset: bytes - Int64(tail.count), count: tail.count), tail)
        XCTAssertTrue(try sameBytes(source, exported))
    }

    func testOpenOfTenGigabyteAttachmentDoesNotReadThePayload() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("huge.floretta")
        let payload: UInt64 = 10 * 1024 * 1024 * 1024
        let range = try writeSparsePackage(archive, payload: payload)
        let before = residentBytes()
        let opened = try openTracking(archive, files: POSIXStreamingFiles())
        let after = residentBytes()
        XCTAssertEqual(opened.package.document.title, "大包")
        XCTAssertEqual(opened.package.directory.attachments.count, 1)
        XCTAssertEqual(opened.package.directory.attachments[0].byteCount, payload)
        XCTAssertFalse(opened.touchedPayload)
        XCTAssertLessThan(opened.bytesRead, 1_000_000)
        XCTAssertGreaterThan(range.count, 1_000_000)
        if before > 0, after > 0 {
            XCTAssertLessThan(after - before, Int64(StreamingBudget.openRamDeltaBytes))
        }
    }

    func testZIP64LocalHeaderDoesNotEmbedThePayload() {
        let name = "assets/\(String(repeating: "a", count: 64)).bin"
        let header = ZipStoredFormatting.localHeader(name: name, crc32: 1, size: 5 * 1024 * 1024 * 1024)
        XCTAssertLessThan(header.count, 256)
        XCTAssertEqual(header[header.startIndex + 18], 0xFF)
        XCTAssertEqual(header[header.startIndex + 22], 0xFF)
        XCTAssertTrue(header.contains(0x01))
    }

    func testThumbnailLRUDropsTheOldestWithinTheCap() throws {
        let entries = [
            ThumbnailCacheEntry(key: "old", byteCount: 150, lastUsed: 1),
            ThumbnailCacheEntry(key: "new", byteCount: 100, lastUsed: 5),
        ]
        XCTAssertEqual(
            ThumbnailDiskBudget.victims(entries: entries, incomingBytes: 80, maxBytes: 200),
            ["old"]
        )
        XCTAssertEqual(
            ThumbnailDiskBudget.victims(entries: entries, incomingBytes: 10, maxBytes: StreamingBudget.thumbnailCacheBytes),
            []
        )

        let directory = try makeDirectory()
        let cache = ThumbnailFileCache(directory: directory, maxBytes: 30)
        let older = String(repeating: "a", count: 64)
        let newer = String(repeating: "b", count: 64)
        try cache.store(Data(repeating: 1, count: 20), for: older)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: cache.fileURL(for: older).path
        )
        try cache.store(Data(repeating: 2, count: 20), for: newer)
        XCTAssertFalse(cache.contains(older))
        XCTAssertTrue(cache.contains(newer))
        XCTAssertLessThanOrEqual(try cache.totalBytes(), 30)
    }

    func testThumbnailsUnloadOutsideTheViewport() {
        let near = AttachmentViewportRect(minX: 0, minY: 0, maxX: 10, maxY: 10)
        let far = AttachmentViewportRect(minX: 500, minY: 500, maxX: 520, maxY: 520)
        let viewport = AttachmentViewportRect(minX: -1, minY: -1, maxX: 20, maxY: 20)
        let visible = ThumbnailResidence.visibleHashes(
            nodes: [(near, ["aa"]), (far, ["bb"])],
            viewport: viewport
        )
        XCTAssertEqual(visible, ["aa"])
        XCTAssertEqual(ThumbnailResidence.retained(loaded: ["aa", "bb"], visible: visible), ["aa"])
    }

    func testAttachmentDirectoryIsExcludedFromBackup() throws {
        let directory = try makeDirectory()
        let exclusion = RecordingExclusion()
        let root = try AttachmentDirectory.prepare(applicationSupport: directory, exclusion: exclusion)
        XCTAssertTrue(root.path.contains("Attachments"))
        XCTAssertEqual(exclusion.urls.count, 3)
        XCTAssertTrue(exclusion.urls.allSatisfy { $0.path.contains("Attachments") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("thumbnails").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("spill").path))
    }

    func testNodeShowsEachAttachmentSizeAndTheDocumentTotal() throws {
        let first = NodeAttachment(sha256: String(repeating: "a", count: 64), fileExtension: "png", byteCount: 100, filename: "a.png")
        let second = NodeAttachment(sha256: String(repeating: "b", count: 64), fileExtension: "mp3", byteCount: 50, filename: "b.mp3")
        let shared = NodeAttachment(sha256: first.sha256, fileExtension: "png", byteCount: 100, filename: "a.png")
        var root = MindMapNode(text: "根", attachments: [first])
        root.children = [MindMapNode(text: "子", attachments: [second, shared])]
        let document = MindMapDocument(title: "合计", createdAt: stamped, modifiedAt: stamped, roots: [root])
        XCTAssertEqual(root.attachmentSizeLabel, "a.png 100 B")
        XCTAssertEqual(document.roots[0].children[0].attachmentSizeLabel, "b.mp3 50 B\na.png 100 B")
        XCTAssertEqual(AttachmentTotals.uniqueReferencedBytes(document), 150)
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded, document)
        let bare = try FlorettaCodec.encode(sampleDocument(title: "无"))
        let text = try XCTUnwrap(String(data: bare, encoding: .utf8))
        XCTAssertFalse(text.contains("attachments"))
    }

    private func hash(_ url: URL, files: POSIXStreamingFiles) throws -> HashedAttachment {
        let reader = try files.openReader(at: url)
        let hashed = try FlorettaStreamingDocument.hashSource(reader, filename: url.lastPathComponent)
        try reader.close()
        return hashed
    }

    private func openTracking(_ url: URL, files: POSIXStreamingFiles) throws -> (package: OpenedFloretta, touchedPayload: Bool, bytesRead: Int) {
        let reader = try files.openReader(at: url)
        guard let tracking = reader as? TrackingReader else {
            XCTFail("expected tracking reader")
            try reader.close()
            throw DocumentContainerError.corrupt("test reader")
        }
        let opened = try FlorettaStreamingDocument.open(tracking)
        let payload = opened.directory.attachments.map { entry in
            Int64(entry.dataOffset)..<(Int64(entry.dataOffset) + Int64(entry.byteCount))
        }
        let touched = tracking.ranges.contains { range in
            payload.contains { range.overlaps($0) }
        }
        let total = tracking.total
        try reader.close()
        return (opened, touched, total)
    }

    private func sampleDocument(title: String) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "根")]
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaStreamingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func archiveByteCount(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func residentBytes() -> Int64 {
        guard let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n") where line.hasPrefix("VmRSS:") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, let kibibytes = Int64(parts[1]) {
                return kibibytes * 1024
            }
        }
        return 0
    }

    private func writeSparse(_ url: URL, size: Int64, head: Data, tail: Data) throws {
        let fd = DarwinOrGlibc.openWrite(url.path)
        guard fd >= 0 else { throw POSIXError.errno }
        defer { _ = DarwinOrGlibc.close(fd) }
        if ftruncate(fd, off_t(size)) != 0 { throw POSIXError.errno }
        try writeAll(fd, head, at: 0)
        if !tail.isEmpty {
            try writeAll(fd, tail, at: off_t(size - Int64(tail.count)))
        }
    }

    private func writeSparsePackage(_ url: URL, payload: UInt64) throws -> Range<Int64> {
        let document = MindMapDocument(
            title: "大包",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "根")]
        )
        let documentData = try FlorettaCodec.encode(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let metadataData = try encoder.encode(FlorettaMetadata(document: document))
        let assetName = "assets/\(String(repeating: "ab", count: 32)).bin"
        let documentHeader = ZipStoredFormatting.localHeader(
            name: "document.json",
            crc32: zipCRC32(documentData),
            size: UInt64(documentData.count)
        )
        let metadataHeader = ZipStoredFormatting.localHeader(
            name: "metadata.json",
            crc32: zipCRC32(metadataData),
            size: UInt64(metadataData.count)
        )
        let assetHeader = ZipStoredFormatting.localHeader(name: assetName, crc32: 0, size: payload)
        let documentOffset: UInt64 = 0
        let metadataOffset = UInt64(documentHeader.count + documentData.count)
        let assetOffset = metadataOffset + UInt64(metadataHeader.count + metadataData.count)
        let dataOffset = assetOffset + UInt64(assetHeader.count)
        let centralOffset = dataOffset + payload
        var central = Data()
        central.append(ZipStoredFormatting.centralHeader(
            name: assetName,
            crc32: 0,
            size: payload,
            localHeaderOffset: assetOffset
        ))
        central.append(ZipStoredFormatting.centralHeader(
            name: "document.json",
            crc32: zipCRC32(documentData),
            size: UInt64(documentData.count),
            localHeaderOffset: documentOffset
        ))
        central.append(ZipStoredFormatting.centralHeader(
            name: "metadata.json",
            crc32: zipCRC32(metadataData),
            size: UInt64(metadataData.count),
            localHeaderOffset: metadataOffset
        ))
        let closing = ZipStoredFormatting.closingRecord(
            entryCount: 3,
            centralDirectorySize: UInt64(central.count),
            centralDirectoryOffset: centralOffset
        )
        let fd = DarwinOrGlibc.openWrite(url.path)
        guard fd >= 0 else { throw POSIXError.errno }
        defer { _ = DarwinOrGlibc.close(fd) }
        try writeAll(fd, documentHeader + documentData, at: off_t(documentOffset))
        try writeAll(fd, metadataHeader + metadataData, at: off_t(metadataOffset))
        try writeAll(fd, assetHeader, at: off_t(assetOffset))
        try writeAll(fd, central, at: off_t(centralOffset))
        try writeAll(fd, closing, at: off_t(centralOffset) + off_t(central.count))
        return Int64(dataOffset)..<(Int64(dataOffset) + Int64(payload))
    }

    private func writeAll(_ fd: Int32, _ data: Data, at offset: off_t) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let n = pwrite(fd, base.advanced(by: written), raw.count - written, offset + off_t(written))
                if n < 0 { throw POSIXError.errno }
                written += n
            }
        }
    }

    private func readRange(_ url: URL, offset: Int64, count: Int) throws -> Data {
        let reader = try POSIXReader(url: url)
        defer { try? reader.close() }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
        defer { pointer.deallocate() }
        let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: count)
        let n = try reader.read(at: offset, into: buffer)
        return Data(buffer.prefix(n))
    }

    private func sameBytes(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let left = try POSIXReader(url: lhs)
        let right = try POSIXReader(url: rhs)
        defer {
            try? left.close()
            try? right.close()
        }
        guard left.count == right.count else { return false }
        let size = 64 * 1024
        let a = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        let b = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        defer {
            a.deallocate()
            b.deallocate()
        }
        var offset: Int64 = 0
        while offset < left.count {
            let sliceA = UnsafeMutableRawBufferPointer(start: a, count: size)
            let sliceB = UnsafeMutableRawBufferPointer(start: b, count: size)
            let readA = try left.read(at: offset, into: sliceA)
            let readB = try right.read(at: offset, into: sliceB)
            if readA != readB || readA == 0 { return false }
            if memcmp(a, b, readA) != 0 { return false }
            offset += Int64(readA)
        }
        return true
    }
}

private final class RecordingExclusion: BackupExclusionPort {
    var urls: [URL] = []
    func excludeFromBackup(_ url: URL) throws {
        urls.append(url)
    }
}

private final class POSIXReader: RandomAccessReader {
    let count: Int64
    private var fd: Int32

    init(url: URL) throws {
        fd = DarwinOrGlibc.openRead(url.path)
        guard fd >= 0 else { throw POSIXError.errno }
        let end = lseek(fd, 0, SEEK_END)
        guard end >= 0 else { throw POSIXError.errno }
        count = Int64(end)
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        let n = pread(fd, base, buffer.count, off_t(offset))
        if n < 0 { throw POSIXError.errno }
        return n
    }

    func close() throws {
        if fd >= 0 {
            _ = DarwinOrGlibc.close(fd)
            fd = -1
        }
    }
}

private final class POSIXWriter: SequentialByteWriter {
    private var fd: Int32

    init(url: URL) throws {
        fd = DarwinOrGlibc.openWrite(url.path)
        guard fd >= 0 else { throw POSIXError.errno }
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return }
        var written = 0
        while written < buffer.count {
            let n = DarwinOrGlibc.write(fd, base.advanced(by: written), buffer.count - written)
            if n < 0 { throw POSIXError.errno }
            written += n
        }
    }

    func close() throws {
        if fd >= 0 {
            _ = DarwinOrGlibc.close(fd)
            fd = -1
        }
    }
}

private enum DarwinOrGlibc {
    static func openRead(_ path: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, O_RDONLY)
        #else
        Glibc.open(path, O_RDONLY)
        #endif
    }

    static func openWrite(_ path: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #else
        Glibc.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #endif
    }

    static func close(_ fd: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }

    static func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #else
        Glibc.write(fd, buffer, count)
        #endif
    }
}

private final class TrackingReader: RandomAccessReader {
    let inner: POSIXReader
    var count: Int64 { inner.count }
    var ranges: [Range<Int64>] = []
    var maxRead = 0
    var total = 0

    init(_ inner: POSIXReader) {
        self.inner = inner
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        maxRead = max(maxRead, buffer.count)
        let n = try inner.read(at: offset, into: buffer)
        if n > 0 {
            ranges.append(offset..<(offset + Int64(n)))
            total += n
        }
        return n
    }

    func close() throws {
        try inner.close()
    }
}

private final class POSIXStreamingFiles: StreamingFilePort {
    private var readers: [TrackingReader] = []

    var maxRead: Int { readers.map(\.maxRead).max() ?? 0 }

    func byteCount(at url: URL) throws -> Int64 {
        let reader = try POSIXReader(url: url)
        defer { try? reader.close() }
        return reader.count
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isZip(at url: URL) throws -> Bool {
        let reader = try POSIXReader(url: url)
        defer { try? reader.close() }
        guard reader.count >= 2 else { return false }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 2, alignment: 1)
        defer { pointer.deallocate() }
        let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: 2)
        let n = try reader.read(at: 0, into: buffer)
        return n == 2 && buffer[0] == 0x50 && buffer[1] == 0x4B
    }

    func openReader(at url: URL) throws -> RandomAccessReader {
        let tracking = TrackingReader(try POSIXReader(url: url))
        readers.append(tracking)
        return tracking
    }

    func openWriter(at url: URL) throws -> SequentialByteWriter {
        try POSIXWriter(url: url)
    }

    func makeTemporary(nextTo url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(".\(UUID().uuidString).partial")
    }

    func replace(destination: URL, with temporary: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    func remove(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
    }

}

private enum POSIXError: Error {
    case errno
}

