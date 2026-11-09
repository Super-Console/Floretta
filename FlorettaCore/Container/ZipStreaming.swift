import Foundation

public struct ZipStoredEntry: Equatable, Sendable {
    public var name: String
    public var method: UInt16
    public var crc32: UInt32
    public var byteCount: UInt64
    public var localHeaderOffset: UInt64
    public var dataOffset: UInt64

    public init(
        name: String,
        method: UInt16,
        crc32: UInt32,
        byteCount: UInt64,
        localHeaderOffset: UInt64,
        dataOffset: UInt64
    ) {
        self.name = name
        self.method = method
        self.crc32 = crc32
        self.byteCount = byteCount
        self.localHeaderOffset = localHeaderOffset
        self.dataOffset = dataOffset
    }

    public var sha256: String? { AttachmentNames.parseAsset(name)?.sha256 }
}

public struct ZipDirectory: Equatable, Sendable {
    public var entries: [ZipStoredEntry]

    public init(entries: [ZipStoredEntry]) {
        self.entries = entries
    }

    public var attachments: [ZipStoredEntry] {
        entries.filter { AttachmentNames.parseAsset($0.name) != nil }
    }

    /// Unique `assets/` bytes. The same sha256 counts once.
    public var storedAttachmentBytes: Int64 {
        var seen: Set<String> = []
        var total: Int64 = 0
        for entry in attachments {
            guard let hash = entry.sha256, seen.insert(hash).inserted else { continue }
            let count = min(entry.byteCount, UInt64(Int64.max))
            total += Int64(count)
        }
        return total
    }
}

public struct HashedAttachment: Equatable, Sendable {
    public var sha256: String
    public var crc32: UInt32
    public var byteCount: UInt64
    public var fileExtension: String
    public var filename: String

    public init(sha256: String, crc32: UInt32, byteCount: UInt64, fileExtension: String, filename: String) {
        self.sha256 = sha256
        self.crc32 = crc32
        self.byteCount = byteCount
        self.fileExtension = fileExtension
        self.filename = filename
    }

    public var assetName: String {
        AttachmentNames.assetName(sha256: sha256, fileExtension: fileExtension)
    }

    public func nodeAttachment() throws -> NodeAttachment {
        guard byteCount <= UInt64(Int64.max) else {
            throw DocumentContainerError.overLimit("Attachment is larger than the supported byte count.")
        }
        return NodeAttachment(
            sha256: sha256,
            fileExtension: fileExtension,
            byteCount: Int64(byteCount),
            filename: filename
        )
    }
}

public struct OpenedFloretta: Equatable, Sendable {
    public var document: MindMapDocument
    public var metadata: FlorettaMetadata
    public var directory: ZipDirectory

    public init(document: MindMapDocument, metadata: FlorettaMetadata, directory: ZipDirectory) {
        self.document = document
        self.metadata = metadata
        self.directory = directory
    }
}

/// Header bytes shared by the streaming writer and by tests that build a sparse package.
public enum ZipStoredFormatting {
    public static func localHeader(name: String, crc32: UInt32, size: UInt64) -> Data {
        let nameData = Data(name.utf8)
        let zip64 = size >= 0xFFFF_FFFF
        var extra = Data()
        if zip64 {
            var payload = Data()
            appendU64(size, to: &payload)
            appendU64(size, to: &payload)
            appendU16(1, to: &extra)
            appendU16(UInt16(payload.count), to: &extra)
            extra.append(payload)
        }
        var header = Data()
        appendU32(0x0403_4B50, to: &header)
        appendU16(zip64 ? 45 : 20, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU32(crc32, to: &header)
        appendU32(zip64 ? 0xFFFF_FFFF : UInt32(size), to: &header)
        appendU32(zip64 ? 0xFFFF_FFFF : UInt32(size), to: &header)
        appendU16(UInt16(nameData.count), to: &header)
        appendU16(UInt16(extra.count), to: &header)
        header.append(nameData)
        header.append(extra)
        return header
    }

    public static func centralHeader(
        name: String,
        crc32: UInt32,
        size: UInt64,
        localHeaderOffset: UInt64
    ) -> Data {
        let nameData = Data(name.utf8)
        let size64 = size >= 0xFFFF_FFFF
        let offset64 = localHeaderOffset >= 0xFFFF_FFFF
        var payload = Data()
        if size64 {
            appendU64(size, to: &payload)
            appendU64(size, to: &payload)
        }
        if offset64 {
            appendU64(localHeaderOffset, to: &payload)
        }
        var extra = Data()
        if !payload.isEmpty {
            appendU16(1, to: &extra)
            appendU16(UInt16(payload.count), to: &extra)
            extra.append(payload)
        }
        let zip64 = !extra.isEmpty
        var header = Data()
        appendU32(0x0201_4B50, to: &header)
        appendU16(zip64 ? 45 : 20, to: &header)
        appendU16(zip64 ? 45 : 20, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU32(crc32, to: &header)
        appendU32(size64 ? 0xFFFF_FFFF : UInt32(size), to: &header)
        appendU32(size64 ? 0xFFFF_FFFF : UInt32(size), to: &header)
        appendU16(UInt16(nameData.count), to: &header)
        appendU16(UInt16(extra.count), to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU16(0, to: &header)
        appendU32(0, to: &header)
        appendU32(offset64 ? 0xFFFF_FFFF : UInt32(localHeaderOffset), to: &header)
        header.append(nameData)
        header.append(extra)
        return header
    }

    public static func closingRecord(
        entryCount: UInt64,
        centralDirectorySize: UInt64,
        centralDirectoryOffset: UInt64
    ) -> Data {
        let count64 = entryCount >= 0xFFFF
        let size64 = centralDirectorySize >= 0xFFFF_FFFF
        let offset64 = centralDirectoryOffset >= 0xFFFF_FFFF
        var record = Data()
        if count64 || size64 || offset64 {
            var zip64 = Data()
            appendU32(0x0606_4B50, to: &zip64)
            appendU64(44, to: &zip64)
            appendU16(45, to: &zip64)
            appendU16(45, to: &zip64)
            appendU32(0, to: &zip64)
            appendU32(0, to: &zip64)
            appendU64(entryCount, to: &zip64)
            appendU64(entryCount, to: &zip64)
            appendU64(centralDirectorySize, to: &zip64)
            appendU64(centralDirectoryOffset, to: &zip64)
            let zip64Offset = centralDirectoryOffset + centralDirectorySize
            var locator = Data()
            appendU32(0x0706_4B50, to: &locator)
            appendU32(0, to: &locator)
            appendU64(zip64Offset, to: &locator)
            appendU32(1, to: &locator)
            record.append(zip64)
            record.append(locator)
        }
        appendU32(0x0605_4B50, to: &record)
        appendU16(0, to: &record)
        appendU16(0, to: &record)
        appendU16(count64 ? 0xFFFF : UInt16(entryCount), to: &record)
        appendU16(count64 ? 0xFFFF : UInt16(entryCount), to: &record)
        appendU32(size64 ? 0xFFFF_FFFF : UInt32(centralDirectorySize), to: &record)
        appendU32(offset64 ? 0xFFFF_FFFF : UInt32(centralDirectoryOffset), to: &record)
        appendU16(0, to: &record)
        return record
    }
}

public enum FlorettaStreamingDocument {
    public static func open(_ reader: RandomAccessReader) throws -> OpenedFloretta {
        try withChunk { chunk in
            let directory = try readDirectory(reader, chunk: chunk)
            let documentData = try readNamed("document.json", in: directory, from: reader, chunk: chunk)
            let metadataData = try readNamed("metadata.json", in: directory, from: reader, chunk: chunk)
            let document: MindMapDocument
            do {
                document = try FlorettaCodec.decode(documentData)
            } catch let error as FlorettaCodecError {
                throw DocumentContainerError.document(error)
            } catch {
                throw DocumentContainerError.corrupt("document.json could not be read.")
            }
            let metadata: FlorettaMetadata
            do {
                metadata = try JSONDecoder().decode(FlorettaMetadata.self, from: metadataData)
            } catch let error as DocumentContainerError {
                throw error
            } catch {
                throw DocumentContainerError.corrupt("metadata.json could not be read.")
            }
            return OpenedFloretta(document: document, metadata: metadata, directory: directory)
        }
    }

    /// One pass. The hash state is fixed-size; `reader` is asked only for `chunkBytes` at a time.
    public static func hashSource(_ reader: RandomAccessReader, filename: String) throws -> HashedAttachment {
        guard reader.count >= 0 else {
            throw DocumentContainerError.corrupt("Attachment length is negative.")
        }
        var sha = SHA256Streaming()
        var crc = CRC32Streaming()
        try withChunk { chunk in
            try streamCopy(
                from: reader,
                offset: 0,
                count: UInt64(reader.count),
                chunk: chunk,
                to: nil,
                sha: &sha,
                crc: &crc
            )
        }
        let digest = sha.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return HashedAttachment(
            sha256: hex,
            crc32: crc.finish(),
            byteCount: UInt64(reader.count),
            fileExtension: AttachmentNames.fileExtension(of: filename),
            filename: filename
        )
    }

    public static func exportAttachment(
        _ entry: ZipStoredEntry,
        from reader: RandomAccessReader,
        to writer: SequentialByteWriter
    ) throws {
        guard entry.method == 0 else {
            throw DocumentContainerError.corrupt("Attachment \(entry.name) is compressed.")
        }
        try withChunk { chunk in
            try copyChunks(from: reader, offset: entry.dataOffset, count: entry.byteCount, chunk: chunk, to: writer)
        }
    }

    /// Checks each `assets/` entry in chunks. A mismatch names that attachment.
    /// Catalog `open` does not call this, so a 10GB package can still be indexed without reading the payload.
    public static func verifyInventory(_ reader: RandomAccessReader, opened: OpenedFloretta) throws {
        var failures: [AssetCorruption] = []
        let stored = Set(opened.directory.attachments.compactMap(\.sha256))
        try withChunk { chunk in
            for entry in opened.directory.attachments {
                let parsed = AttachmentNames.parseAsset(entry.name)
                let sha = parsed?.sha256 ?? ""
                let filename = sha.isEmpty
                    ? entry.name
                    : AssetInventory.filenames(for: sha, in: opened.document)
                if entry.method != 0 {
                    failures.append(AssetCorruption(
                        filename: filename,
                        sha256: sha,
                        entryName: entry.name,
                        reason: .compressed
                    ))
                    continue
                }
                guard let parsed else {
                    failures.append(AssetCorruption(
                        filename: filename,
                        sha256: sha,
                        entryName: entry.name,
                        reason: .malformedName
                    ))
                    continue
                }
                var digest = SHA256Streaming()
                var crc = CRC32Streaming()
                do {
                    try streamCopy(
                        from: reader,
                        offset: entry.dataOffset,
                        count: entry.byteCount,
                        chunk: chunk,
                        to: nil,
                        sha: &digest,
                        crc: &crc
                    )
                } catch {
                    failures.append(AssetCorruption(
                        filename: filename,
                        sha256: parsed.sha256,
                        entryName: entry.name,
                        reason: .unreadable
                    ))
                    continue
                }
                let actual = AssetInventory.hex(digest.finalize())
                if actual != parsed.sha256 {
                    failures.append(AssetCorruption(
                        filename: filename,
                        sha256: parsed.sha256,
                        entryName: entry.name,
                        reason: .hashMismatch(actual: actual)
                    ))
                }
            }
        }
        failures.append(contentsOf: AssetInventory.missingReferences(in: opened.document, stored: stored))
        if let error = AssetInventory.error(from: failures) {
            throw error
        }
    }

    /// Rewrites `archive` (central directory only, then chunked payload copies) plus an optional new asset.
    /// A sha256 that is already stored is not written again. `retaining` keeps bytes a snapshot still names.
    public static func rewrite(
        archive: RandomAccessReader?,
        document: MindMapDocument,
        metadata: FlorettaMetadata,
        source: (reader: RandomAccessReader, hashed: HashedAttachment)?,
        retaining assetHashes: Set<String> = [],
        to writer: SequentialByteWriter
    ) throws -> ZipDirectory {
        try withChunk { chunk in
            let existing = try archive.map { try readDirectory($0, chunk: chunk) } ?? ZipDirectory(entries: [])
            let referenced = AttachmentReferences.hashes(in: document)
            let documentData = try FlorettaCodec.encode(document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let metadataData = try encoder.encode(metadata)
            var planned: [Planned] = [
                Planned(name: "document.json", crc32: zipCRC32(documentData), size: UInt64(documentData.count), body: .inline(documentData)),
                Planned(name: "metadata.json", crc32: zipCRC32(metadataData), size: UInt64(metadataData.count), body: .inline(metadataData)),
            ]
            for entry in existing.entries {
                if entry.name == "document.json" || entry.name == "metadata.json" { continue }
                if let asset = AttachmentNames.parseAsset(entry.name) {
                    if !referenced.contains(asset.sha256) && !assetHashes.contains(asset.sha256) { continue }
                } else if entry.name.hasPrefix("assets/") {
                    throw DocumentContainerError.corrupt("Asset name \(entry.name) is not assets/<sha256>.<ext>.")
                }
                if entry.method != 0 {
                    throw DocumentContainerError.corrupt("Attachment \(entry.name) is compressed.")
                }
                guard let archive else {
                    throw DocumentContainerError.corrupt("Missing archive for \(entry.name).")
                }
                planned.append(Planned(
                    name: entry.name,
                    crc32: entry.crc32,
                    size: entry.byteCount,
                    body: .copy(archive, entry.dataOffset)
                ))
            }
            if let source {
                let name = source.hashed.assetName
                let already = planned.contains {
                    AttachmentNames.parseAsset($0.name)?.sha256 == source.hashed.sha256
                }
                if !already {
                    planned.append(Planned(
                        name: name,
                        crc32: source.hashed.crc32,
                        size: source.hashed.byteCount,
                        body: .copy(source.reader, 0)
                    ))
                }
            }
            planned.sort { $0.name < $1.name }
            var written: [ZipStoredEntry] = []
            var cursor: UInt64 = 0
            for item in planned {
                let header = ZipStoredFormatting.localHeader(name: item.name, crc32: item.crc32, size: item.size)
                let localOffset = cursor
                try writer.write(header)
                cursor = try add(cursor, UInt64(header.count))
                let dataOffset = cursor
                switch item.body {
                case .inline(let data):
                    try writer.write(data)
                case .copy(let reader, let offset):
                    try copyChunks(from: reader, offset: offset, count: item.size, chunk: chunk, to: writer)
                }
                cursor = try add(cursor, item.size)
                written.append(ZipStoredEntry(
                    name: item.name,
                    method: 0,
                    crc32: item.crc32,
                    byteCount: item.size,
                    localHeaderOffset: localOffset,
                    dataOffset: dataOffset
                ))
            }
            let centralStart = cursor
            for entry in written {
                let header = ZipStoredFormatting.centralHeader(
                    name: entry.name,
                    crc32: entry.crc32,
                    size: entry.byteCount,
                    localHeaderOffset: entry.localHeaderOffset
                )
                try writer.write(header)
                cursor = try add(cursor, UInt64(header.count))
            }
            let closing = ZipStoredFormatting.closingRecord(
                entryCount: UInt64(written.count),
                centralDirectorySize: cursor - centralStart,
                centralDirectoryOffset: centralStart
            )
            try writer.write(closing)
            return ZipDirectory(entries: written)
        }
    }

    /// Writes a ZIP at `url`. Attachments already stored at `url` are copied through
    /// in chunks. Pass `copyingAssetsFrom` when the new path is not the file that
    /// already holds the bytes (export). Refuses to overwrite a legacy JSON `.floretta`.
    /// `appending` is stored unless its sha256 is already in the archive.
    @discardableResult
    public static func save(
        document: MindMapDocument,
        to url: URL,
        files: any StreamingFilePort,
        copyingAssetsFrom origin: URL? = nil,
        appending source: (url: URL, hashed: HashedAttachment)? = nil,
        snapshots: SnapshotRetention = .standard
    ) throws -> ZipDirectory {
        if files.fileExists(at: url), try !files.isZip(at: url) {
            throw DocumentContainerError.refusesToOverwriteLegacy
        }
        let archiveURL = origin ?? url
        var staged = StagedSnapshots(retainHashes: [], obsolete: [])
        if snapshots.limit > 0, files.fileExists(at: url), try files.isZip(at: url) {
            let previousReader = try files.openReader(at: url)
            let previous: OpenedFloretta
            do {
                previous = try open(previousReader)
                try previousReader.close()
            } catch {
                try? previousReader.close()
                throw error
            }
            let previousJSON = try FlorettaCodec.encode(previous.document)
            staged = try DocumentSnapshots.stage(previous: previousJSON, for: url, retention: snapshots)
        }
        let temporary = try files.makeTemporary(nextTo: url)
        guard temporary.lastPathComponent == AtomicFileBytes.partialURL(for: url).lastPathComponent else {
            try? files.remove(at: temporary)
            throw DocumentContainerError.corrupt("Temporary file is not the stable partial name.")
        }
        var archive: RandomAccessReader?
        var sourceReader: RandomAccessReader?
        let writer = try files.openWriter(at: temporary)
        do {
            if files.fileExists(at: archiveURL), try files.isZip(at: archiveURL) {
                archive = try files.openReader(at: archiveURL)
            }
            let hashed = source?.hashed
            if let source {
                sourceReader = try files.openReader(at: source.url)
            }
            let paired: (reader: RandomAccessReader, hashed: HashedAttachment)?
            if let sourceReader, let hashed {
                paired = (sourceReader, hashed)
            } else {
                paired = nil
            }
            let directory = try rewrite(
                archive: archive,
                document: document,
                metadata: FlorettaMetadata(document: document),
                source: paired,
                retaining: staged.retainHashes,
                to: writer
            )
            try writer.synchronize()
            try writer.close()
            try archive?.close()
            try sourceReader?.close()
            archive = nil
            sourceReader = nil
            try files.replace(destination: url, with: temporary)
            DocumentSnapshots.discard(staged.obsolete)
            return directory
        } catch {
            try? writer.close()
            try? archive?.close()
            try? sourceReader?.close()
            try? files.remove(at: temporary)
            throw error
        }
    }

    private struct Planned {
        enum Body {
            case inline(Data)
            case copy(RandomAccessReader, UInt64)
        }

        var name: String
        var crc32: UInt32
        var size: UInt64
        var body: Body
    }

    private static func readDirectory(
        _ reader: RandomAccessReader,
        chunk: UnsafeMutableRawBufferPointer
    ) throws -> ZipDirectory {
        guard reader.count >= 22 else {
            throw DocumentContainerError.corrupt("Zip is too small.")
        }
        var materialized = 0
        let tail = try readExactly(reader, offset: reader.count - 22, count: 22, chunk: chunk, materialized: &materialized)
        guard readU32(tail, 0) == 0x0605_4B50 else {
            throw DocumentContainerError.corrupt("Zip directory is missing.")
        }
        var entryCount = UInt64(readU16(tail, 10))
        var centralSize = UInt64(readU32(tail, 12))
        var centralOffset = UInt64(readU32(tail, 16))
        let commentLength = Int(readU16(tail, 20))
        if commentLength != 0 {
            throw DocumentContainerError.corrupt("Zip comment is not supported on the streaming open path.")
        }
        if entryCount == 0xFFFF || centralSize == 0xFFFF_FFFF || centralOffset == 0xFFFF_FFFF {
            let locatorOffset = reader.count - 22 - 20
            guard locatorOffset >= 0 else {
                throw DocumentContainerError.corrupt("Zip64 locator is missing.")
            }
            let locator = try readExactly(reader, offset: locatorOffset, count: 20, chunk: chunk, materialized: &materialized)
            guard readU32(locator, 0) == 0x0706_4B50 else {
                throw DocumentContainerError.corrupt("Zip64 locator is missing.")
            }
            let zip64Offset = readU64(locator, 8)
            let zip64 = try readExactly(reader, offset: try int64(zip64Offset), count: 56, chunk: chunk, materialized: &materialized)
            guard readU32(zip64, 0) == 0x0606_4B50 else {
                throw DocumentContainerError.corrupt("Zip64 directory is missing.")
            }
            entryCount = readU64(zip64, 32)
            centralSize = readU64(zip64, 40)
            centralOffset = readU64(zip64, 48)
        }
        if centralSize > UInt64(StreamingBudget.maxMaterializedOpenBytes) {
            throw DocumentContainerError.overLimit("Zip directory exceeds the open budget.")
        }
        if entryCount > centralSize {
            throw DocumentContainerError.corrupt("Zip directory count is invalid.")
        }
        let central = try readExactly(
            reader,
            offset: try int64(centralOffset),
            count: Int(centralSize),
            chunk: chunk,
            materialized: &materialized
        )
        var cursor = 0
        var entries: [ZipStoredEntry] = []
        for _ in 0..<entryCount {
            guard cursor + 46 <= central.count else {
                throw DocumentContainerError.corrupt("Zip directory entry is truncated.")
            }
            guard readU32(central, cursor) == 0x0201_4B50 else {
                throw DocumentContainerError.corrupt("Zip directory entry is invalid.")
            }
            let flags = Int(readU16(central, cursor + 8))
            let method = readU16(central, cursor + 10)
            let crc = readU32(central, cursor + 16)
            var compressedSize = UInt64(readU32(central, cursor + 20))
            var uncompressedSize = UInt64(readU32(central, cursor + 24))
            let nameLength = Int(readU16(central, cursor + 28))
            let extraLength = Int(readU16(central, cursor + 30))
            let commentLength = Int(readU16(central, cursor + 32))
            var localOffset = UInt64(readU32(central, cursor + 42))
            let nameStart = cursor + 46
            let recordEnd = nameStart + nameLength + extraLength + commentLength
            guard recordEnd <= central.count else {
                throw DocumentContainerError.corrupt("Zip directory name is truncated.")
            }
            let nameData = central.subdata(in: (central.startIndex + nameStart)..<(central.startIndex + nameStart + nameLength))
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw DocumentContainerError.corrupt("Zip entry name is not UTF-8.")
            }
            if flags & 0x1 != 0 || flags & 0x8 != 0 {
                throw DocumentContainerError.corrupt("Unsupported zip entry flags.")
            }
            try validateName(name)
            let extraStart = nameStart + nameLength
            let extra = central.subdata(in: (central.startIndex + extraStart)..<(central.startIndex + extraStart + extraLength))
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                let fields = try zip64Fields(
                    extra,
                    needSize: uncompressedSize == 0xFFFF_FFFF || compressedSize == 0xFFFF_FFFF,
                    needOffset: localOffset == 0xFFFF_FFFF
                )
                if uncompressedSize == 0xFFFF_FFFF, let value = fields.uncompressed { uncompressedSize = value }
                if compressedSize == 0xFFFF_FFFF, let value = fields.compressed { compressedSize = value }
                if localOffset == 0xFFFF_FFFF, let value = fields.offset { localOffset = value }
            }
            if method != 0 {
                throw DocumentContainerError.corrupt("Zip entry \(name) is compressed.")
            }
            if compressedSize != uncompressedSize {
                throw DocumentContainerError.corrupt("Zip entry \(name) has a bad stored size.")
            }
            let dataOffset = try localDataOffset(reader, localOffset: localOffset, chunk: chunk, materialized: &materialized)
            if name.hasPrefix("assets/") {
                guard AttachmentNames.parseAsset(name) != nil else {
                    throw DocumentContainerError.corrupt("Asset name \(name) is not assets/<sha256>.<ext>.")
                }
            }
            if !name.hasSuffix("/") {
                entries.append(ZipStoredEntry(
                    name: name,
                    method: method,
                    crc32: crc,
                    byteCount: uncompressedSize,
                    localHeaderOffset: localOffset,
                    dataOffset: dataOffset
                ))
            }
            cursor = recordEnd
        }
        return ZipDirectory(entries: entries)
    }

    private static func localDataOffset(
        _ reader: RandomAccessReader,
        localOffset: UInt64,
        chunk: UnsafeMutableRawBufferPointer,
        materialized: inout Int
    ) throws -> UInt64 {
        let header = try readExactly(
            reader,
            offset: try int64(localOffset),
            count: 30,
            chunk: chunk,
            materialized: &materialized
        )
        guard readU32(header, 0) == 0x0403_4B50 else {
            throw DocumentContainerError.corrupt("Zip entry has a bad header.")
        }
        let nameLength = Int(readU16(header, 26))
        let extraLength = Int(readU16(header, 28))
        let tail = nameLength + extraLength
        if tail > 0 {
            _ = try readExactly(
                reader,
                offset: try int64(try add(localOffset, 30)),
                count: tail,
                chunk: chunk,
                materialized: &materialized
            )
        }
        return try add(localOffset, UInt64(30 + tail))
    }

    private static func readNamed(
        _ name: String,
        in directory: ZipDirectory,
        from reader: RandomAccessReader,
        chunk: UnsafeMutableRawBufferPointer
    ) throws -> Data {
        guard let entry = directory.entries.first(where: { $0.name == name }) else {
            throw DocumentContainerError.missingEntry(name)
        }
        guard entry.method == 0 else {
            throw DocumentContainerError.corrupt("\(name) is compressed.")
        }
        guard entry.byteCount <= UInt64(StreamingBudget.maxMaterializedOpenBytes) else {
            throw DocumentContainerError.overLimit("\(name) exceeds the open budget.")
        }
        var materialized = 0
        return try readExactly(
            reader,
            offset: try int64(entry.dataOffset),
            count: Int(entry.byteCount),
            chunk: chunk,
            materialized: &materialized
        )
    }

    private static func readExactly(
        _ reader: RandomAccessReader,
        offset: Int64,
        count: Int,
        chunk: UnsafeMutableRawBufferPointer,
        materialized: inout Int
    ) throws -> Data {
        if count < 0 {
            throw DocumentContainerError.corrupt("Zip offset is out of range.")
        }
        if materialized > StreamingBudget.maxMaterializedOpenBytes - count {
            throw DocumentContainerError.overLimit("Opening the package would materialize more than \(StreamingBudget.maxMaterializedOpenBytes) bytes.")
        }
        var data = Data()
        data.reserveCapacity(count)
        var got = 0
        while got < count {
            let sliceCount = min(chunk.count, count - got)
            let slice = UnsafeMutableRawBufferPointer(start: chunk.baseAddress, count: sliceCount)
            let read = try reader.read(at: offset + Int64(got), into: slice)
            if read <= 0 {
                throw DocumentContainerError.corrupt("Zip entry is truncated.")
            }
            data.append(contentsOf: slice.prefix(read))
            got += read
        }
        materialized += data.count
        return data
    }

    private static func copyChunks(
        from reader: RandomAccessReader,
        offset: UInt64,
        count: UInt64,
        chunk: UnsafeMutableRawBufferPointer,
        to writer: SequentialByteWriter
    ) throws {
        var remaining = count
        var cursor = offset
        while remaining > 0 {
            let sliceCount = min(UInt64(chunk.count), remaining)
            let slice = UnsafeMutableRawBufferPointer(start: chunk.baseAddress, count: Int(sliceCount))
            let read = try reader.read(at: try int64(cursor), into: slice)
            if read <= 0 {
                throw DocumentContainerError.corrupt("Attachment bytes ended early.")
            }
            try writer.write(UnsafeRawBufferPointer(start: chunk.baseAddress, count: read))
            cursor = try add(cursor, UInt64(read))
            remaining -= UInt64(read)
        }
    }

    private static func streamCopy(
        from reader: RandomAccessReader,
        offset: UInt64,
        count: UInt64,
        chunk: UnsafeMutableRawBufferPointer,
        to writer: SequentialByteWriter?,
        sha: inout SHA256Streaming,
        crc: inout CRC32Streaming
    ) throws {
        var remaining = count
        var cursor = offset
        while remaining > 0 {
            let sliceCount = min(UInt64(chunk.count), remaining)
            let slice = UnsafeMutableRawBufferPointer(start: chunk.baseAddress, count: Int(sliceCount))
            let read = try reader.read(at: try int64(cursor), into: slice)
            if read <= 0 {
                throw DocumentContainerError.corrupt("Attachment bytes ended early.")
            }
            let raw = UnsafeRawBufferPointer(start: chunk.baseAddress, count: read)
            sha.update(raw)
            crc.update(raw)
            try writer?.write(raw)
            cursor = try add(cursor, UInt64(read))
            remaining -= UInt64(read)
        }
    }

    private static func withChunk<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) throws -> T {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: StreamingBudget.chunkBytes, alignment: 64)
        defer { pointer.deallocate() }
        let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: StreamingBudget.chunkBytes)
        return try body(buffer)
    }

    private static func zip64Fields(
        _ extra: Data,
        needSize: Bool,
        needOffset: Bool
    ) throws -> (uncompressed: UInt64?, compressed: UInt64?, offset: UInt64?) {
        var cursor = 0
        while cursor + 4 <= extra.count {
            let id = Int(readU16(extra, cursor))
            let size = Int(readU16(extra, cursor + 2))
            let start = cursor + 4
            guard size >= 0, start + size <= extra.count else {
                throw DocumentContainerError.corrupt("Zip64 extra is truncated.")
            }
            if id == 1 {
                var field = start
                var uncompressed: UInt64?
                var compressed: UInt64?
                var offset: UInt64?
                if needSize {
                    guard field + 16 <= start + size else {
                        throw DocumentContainerError.corrupt("Zip64 size is missing.")
                    }
                    uncompressed = readU64(extra, field)
                    compressed = readU64(extra, field + 8)
                    field += 16
                }
                if needOffset {
                    guard field + 8 <= start + size else {
                        throw DocumentContainerError.corrupt("Zip64 offset is missing.")
                    }
                    offset = readU64(extra, field)
                }
                return (uncompressed, compressed, offset)
            }
            cursor = start + size
        }
        throw DocumentContainerError.corrupt("Zip64 extra is missing.")
    }

    private static func validateName(_ name: String) throws {
        if name.isEmpty || name.hasPrefix("/") || name.contains("\\") || name.contains("..") {
            throw DocumentContainerError.corrupt("Zip entry name is not allowed.")
        }
    }

    private static func int64(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw DocumentContainerError.overLimit("Zip offset does not fit in the reader.")
        }
        return Int64(value)
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow {
            throw DocumentContainerError.overLimit("Zip offset overflowed.")
        }
        return sum
    }
}

private func appendU16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
}

private func appendU32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}

private func appendU64(_ value: UInt64, to data: inout Data) {
    var remaining = value
    for _ in 0..<8 {
        data.append(UInt8(truncatingIfNeeded: remaining))
        remaining >>= 8
    }
}

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset >= 0, offset + 1 < data.count else { return 0 }
    return UInt16(data[data.startIndex + offset])
        | (UInt16(data[data.startIndex + offset + 1]) << 8)
}

private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset >= 0, offset + 3 < data.count else { return 0 }
    return UInt32(data[data.startIndex + offset])
        | (UInt32(data[data.startIndex + offset + 1]) << 8)
        | (UInt32(data[data.startIndex + offset + 2]) << 16)
        | (UInt32(data[data.startIndex + offset + 3]) << 24)
}

private func readU64(_ data: Data, _ offset: Int) -> UInt64 {
    guard offset >= 0, offset + 7 < data.count else { return 0 }
    var value: UInt64 = 0
    for index in 0..<8 {
        value |= UInt64(data[data.startIndex + offset + index]) << (8 * index)
    }
    return value
}
