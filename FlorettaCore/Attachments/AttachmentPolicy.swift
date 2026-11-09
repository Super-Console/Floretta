import Foundation

/// Ceilings shared with `docs/STREAMING.md` and `docs/PERF-BUDGET.md`.
public enum StreamingBudget {
    /// Product soft cap. Not a memory allocation.
    public static let softCapBytes: Int64 = 10 * 1024 * 1024 * 1024
    /// Attachment write peak RAM must stay strictly under this, at any file size.
    public static let writePeakBytes = 32 * 1024 * 1024
    /// Opening a document whose attachments total 10GB must add strictly less than this to process RAM.
    public static let openRamDeltaBytes = 50 * 1024 * 1024
    /// On-disk thumbnail cache cap, inclusive.
    public static let thumbnailCacheBytes: Int64 = 200 * 1024 * 1024
    /// One reusable I/O block. Four of these still sit under the write peak.
    public static let chunkBytes = 1 * 1024 * 1024
    /// Longest edge of a generated thumbnail. ImageIO and the test decoder both use this.
    public static let thumbnailLongestEdge = 256
    /// Central directory plus the two JSON entries materialized while opening.
    public static let maxMaterializedOpenBytes = 40 * 1024 * 1024
}

public enum AttachmentByteFormat {
    public static func label(_ bytes: Int64) -> String {
        let sign: Int64 = bytes < 0 ? -1 : 1
        var size = Double(sign < 0 ? -bytes : bytes)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        let prefix = sign < 0 ? "-" : ""
        if unit == 0 {
            return "\(prefix)\(sign < 0 ? -bytes : bytes) B"
        }
        if size >= 10 {
            return String(format: "%@%.0f %@", prefix, size, units[unit])
        }
        return String(format: "%@%.1f %@", prefix, size, units[unit])
    }
}

public enum AttachmentNames {
    public static func normalizeExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let filtered = trimmed.filter { $0.isLetter || $0.isNumber }
        if filtered.isEmpty { return "bin" }
        return String(filtered.prefix(8))
    }

    public static func assetName(sha256: String, fileExtension: String) -> String {
        "assets/\(sha256).\(normalizeExtension(fileExtension))"
    }

    public static func fileExtension(of filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        return normalizeExtension(ext)
    }

    /// `assets/<64 hex>.<ext>` → hash and extension. Nil when the name is not an asset.
    public static func parseAsset(_ name: String) -> (sha256: String, fileExtension: String)? {
        guard name.hasPrefix("assets/") else { return nil }
        let fileName = String(name.dropFirst("assets/".count))
        let parts = fileName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) else { return nil }
        return (parts[0].lowercased(), normalizeExtension(parts[1]))
    }
}

public enum AttachmentKind {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "webp", "tif", "tiff", "bmp",
    ]

    public static func isImageExtension(_ raw: String) -> Bool {
        imageExtensions.contains(AttachmentNames.normalizeExtension(raw))
    }
}

/// Shown before any byte of the file is read. Sizes come from `stat`.
public struct AttachmentInsertProposal: Equatable, Sendable {
    public var filename: String
    public var fileByteCount: Int64
    public var currentDocumentByteCount: Int64
    public var projectedDocumentByteCount: Int64
    public var exceedsSoftCap: Bool
    public var fileExtension: String

    public init(filename: String, fileByteCount: Int64, currentDocumentByteCount: Int64) {
        self.filename = filename
        let file = max(0, fileByteCount)
        let current = max(0, currentDocumentByteCount)
        self.fileByteCount = file
        self.currentDocumentByteCount = current
        self.projectedDocumentByteCount = Self.saturatingAdd(file, current)
        let cap = StreamingBudget.softCapBytes
        self.exceedsSoftCap = file > cap || projectedDocumentByteCount > cap
        self.fileExtension = AttachmentNames.fileExtension(of: filename)
    }

    public var confirmationMessage: String {
        var lines = [
            "文件大小：\(AttachmentByteFormat.label(fileByteCount))",
            "放入后文档大约：\(AttachmentByteFormat.label(projectedDocumentByteCount))",
            "字节原样放进当前项目，不压缩、不转码。",
        ]
        if exceedsSoftCap {
            lines.append("超过 10GB 软上限。")
        }
        return lines.joined(separator: "\n")
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

public struct NodeAttachment: Equatable, Sendable, Codable {
    public var sha256: String
    public var fileExtension: String
    public var byteCount: Int64
    public var filename: String

    public init(sha256: String, fileExtension: String, byteCount: Int64, filename: String) {
        self.sha256 = sha256
        self.fileExtension = AttachmentNames.normalizeExtension(fileExtension)
        self.byteCount = byteCount
        self.filename = filename
    }
}

extension MindMapNode {
    public var attachmentSizeLabel: String? {
        guard !attachments.isEmpty else { return nil }
        return attachments
            .map { "\($0.filename) \(AttachmentByteFormat.label($0.byteCount))" }
            .joined(separator: "\n")
    }
}

public struct AttachmentReferenceCount: Equatable, Sendable {
    public var sha256: String
    public var fileExtension: String
    public var byteCount: Int64
    public var count: Int

    public init(sha256: String, fileExtension: String, byteCount: Int64, count: Int) {
        self.sha256 = sha256
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.count = count
    }
}

public enum AttachmentReferences {
    /// How many nodes point at each sha256. Order is by hash.
    public static func counts(in document: MindMapDocument) -> [AttachmentReferenceCount] {
        var order: [String] = []
        var tally: [String: AttachmentReferenceCount] = [:]
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                for attachment in node.attachments {
                    if var existing = tally[attachment.sha256] {
                        existing.count += 1
                        tally[attachment.sha256] = existing
                    } else {
                        order.append(attachment.sha256)
                        tally[attachment.sha256] = AttachmentReferenceCount(
                            sha256: attachment.sha256,
                            fileExtension: attachment.fileExtension,
                            byteCount: attachment.byteCount,
                            count: 1
                        )
                    }
                }
                walk(node.children)
            }
        }
        walk(document.roots)
        return order.compactMap { tally[$0] }.sorted { $0.sha256 < $1.sha256 }
    }

    public static func hashes(in document: MindMapDocument) -> Set<String> {
        Set(counts(in: document).map(\.sha256))
    }

    /// Stored asset names whose sha256 no node still references.
    public static func orphans(stored: [ZipStoredEntry], document: MindMapDocument) -> [String] {
        let live = hashes(in: document)
        return stored.compactMap { entry in
            guard let asset = AttachmentNames.parseAsset(entry.name), !live.contains(asset.sha256) else { return nil }
            return entry.name
        }
    }
}

public enum AttachmentTotals {
    public static func uniqueReferencedBytes(_ document: MindMapDocument) -> Int64 {
        var seen: [String: Int64] = [:]
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                for attachment in node.attachments where seen[attachment.sha256] == nil {
                    seen[attachment.sha256] = max(0, attachment.byteCount)
                }
                walk(node.children)
            }
        }
        walk(document.roots)
        return seen.values.reduce(0, +)
    }
}

public struct ThumbnailCacheEntry: Equatable, Sendable {
    public var key: String
    public var byteCount: Int64
    public var lastUsed: Int

    public init(key: String, byteCount: Int64, lastUsed: Int) {
        self.key = key
        self.byteCount = byteCount
        self.lastUsed = lastUsed
    }
}

public enum ThumbnailDiskBudget {
    /// Oldest keys to delete so `entries + incoming` fits in `maxBytes`.
    /// The incoming object itself is never selected. A single incoming object
    /// larger than the cap yields every existing key; the caller still refuses the store.
    public static func victims(
        entries: [ThumbnailCacheEntry],
        incomingBytes: Int64,
        maxBytes: Int64 = StreamingBudget.thumbnailCacheBytes
    ) -> [String] {
        let incoming = max(0, incomingBytes)
        var total = entries.reduce(Int64(0)) { $0 + max(0, $1.byteCount) } + incoming
        guard total > maxBytes else { return [] }
        let ordered = entries.sorted {
            if $0.lastUsed != $1.lastUsed { return $0.lastUsed < $1.lastUsed }
            return $0.key < $1.key
        }
        var doomed: [String] = []
        for entry in ordered {
            if total <= maxBytes { break }
            doomed.append(entry.key)
            total -= max(0, entry.byteCount)
        }
        return doomed
    }
}

public struct AttachmentViewportRect: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public func intersects(_ other: AttachmentViewportRect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }
}

public enum ThumbnailResidence {
    public static func visibleHashes(
        nodes: [(rect: AttachmentViewportRect, hashes: [String])],
        viewport: AttachmentViewportRect
    ) -> Set<String> {
        var visible: Set<String> = []
        for node in nodes where node.rect.intersects(viewport) {
            visible.formUnion(node.hashes)
        }
        return visible
    }

    /// In-memory images that remain after a scroll. Anything outside `visible` is unloaded.
    public static func retained(loaded: Set<String>, visible: Set<String>) -> Set<String> {
        loaded.intersection(visible)
    }
}

public enum AttachmentDirectory {
    public static let folderName = "Attachments"

    public static func root(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Floretta", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    public static func thumbnails(applicationSupport: URL) -> URL {
        root(applicationSupport: applicationSupport).appendingPathComponent("thumbnails", isDirectory: true)
    }

    public static func spill(applicationSupport: URL) -> URL {
        root(applicationSupport: applicationSupport).appendingPathComponent("spill", isDirectory: true)
    }

    /// Creates the cache directories and excludes each one from backup.
    @discardableResult
    public static func prepare(applicationSupport: URL, exclusion: BackupExclusionPort) throws -> URL {
        let directories = [
            root(applicationSupport: applicationSupport),
            thumbnails(applicationSupport: applicationSupport),
            spill(applicationSupport: applicationSupport),
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try exclusion.excludeFromBackup(directory)
        }
        return directories[0]
    }
}

/// Disk cache of thumbnail files. Bytes on disk stay ≤ `maxBytes` by dropping the least recently used.
/// Reads a spill file that was streamed to disk and returns thumbnail bytes.
/// The Apple adapter is `ImageIOThumbnailDecoder` (CGImageSource, longest edge 256).
public protocol ThumbnailDecodingPort: Sendable {
    func downsample(spill: URL, longestEdge: Int) throws -> Data
}

/// In-memory thumbnails. `apply` drops every hash that left the viewport.
public struct ThumbnailMemory: Equatable, Sendable {
    public private(set) var images: [String: Data]

    public init() {
        images = [:]
    }

    public mutating func apply(visible: Set<String>, resolve: (String) -> Data?) {
        let keep = ThumbnailResidence.retained(loaded: Set(images.keys), visible: visible)
        images = images.filter { keep.contains($0.key) }
        for hash in visible where images[hash] == nil {
            if let data = resolve(hash), !data.isEmpty {
                images[hash] = data
            }
        }
    }

    /// Drops hashes that scrolled out. Does not decode.
    public mutating func unload(keeping visible: Set<String>) {
        let keep = ThumbnailResidence.retained(loaded: Set(images.keys), visible: visible)
        images = images.filter { keep.contains($0.key) }
    }

    public mutating func remember(_ data: Data, for hash: String, visible: Set<String>) {
        guard visible.contains(hash), !data.isEmpty else { return }
        images[hash] = data
    }
}

public enum ThumbnailPipeline {
    /// Stream `entry` to `spillDirectory/<sha256>`, downsample from that file, store in `cache`, delete the spill.
    @discardableResult
    public static func materialize(
        entry: ZipStoredEntry,
        archiveURL: URL,
        spillDirectory: URL,
        cache: ThumbnailFileCache,
        decoder: any ThumbnailDecodingPort,
        files: any StreamingFilePort
    ) throws -> Data {
        let spill = try writeSpill(
            entry: entry,
            archiveURL: archiveURL,
            spillDirectory: spillDirectory,
            files: files
        )
        do {
            let thumbnail = try decoder.downsample(spill: spill, longestEdge: StreamingBudget.thumbnailLongestEdge)
            if let hash = entry.sha256 {
                try cache.store(thumbnail, for: hash)
            }
            try? files.remove(at: spill)
            return thumbnail
        } catch {
            try? files.remove(at: spill)
            throw error
        }
    }

    /// Same spill as a thumbnail, then decode at `longestEdge` and delete the spill.
    /// Does not write the disk LRU. Export uses this so a page-resolution image does not evict thumbnails.
    @discardableResult
    public static func decodeSpilled(
        entry: ZipStoredEntry,
        archiveURL: URL,
        spillDirectory: URL,
        files: any StreamingFilePort,
        longestEdge: (URL) -> Int,
        decoder: any ThumbnailDecodingPort
    ) throws -> Data {
        let spill = try writeSpill(
            entry: entry,
            archiveURL: archiveURL,
            spillDirectory: spillDirectory,
            files: files
        )
        do {
            let edge = longestEdge(spill)
            let data = try decoder.downsample(spill: spill, longestEdge: edge)
            try? files.remove(at: spill)
            return data
        } catch {
            try? files.remove(at: spill)
            throw error
        }
    }

    private static func writeSpill(
        entry: ZipStoredEntry,
        archiveURL: URL,
        spillDirectory: URL,
        files: any StreamingFilePort
    ) throws -> URL {
        guard entry.method == 0 else {
            throw DocumentContainerError.corrupt("Attachment \(entry.name) is compressed.")
        }
        guard let hash = entry.sha256 else {
            throw DocumentContainerError.corrupt("Attachment \(entry.name) is not assets/<sha256>.<ext>.")
        }
        let spill = spillDirectory.appendingPathComponent(hash, isDirectory: false)
        let reader = try files.openReader(at: archiveURL)
        let writer = try files.openWriter(at: spill)
        do {
            try FlorettaStreamingDocument.exportAttachment(entry, from: reader, to: writer)
            try writer.close()
            try reader.close()
        } catch {
            try? writer.close()
            try? reader.close()
            try? files.remove(at: spill)
            throw error
        }
        return spill
    }
}

public struct ThumbnailFileCache: Sendable {
    public let directory: URL
    public var maxBytes: Int64

    public init(directory: URL, maxBytes: Int64 = StreamingBudget.thumbnailCacheBytes) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(safe(key), isDirectory: false)
    }

    public func contains(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    public func store(_ data: Data, for key: String) throws {
        if Int64(data.count) > maxBytes {
            throw DocumentContainerError.overLimit("Thumbnail exceeds the \(maxBytes) byte disk cache.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: key)
        try data.write(to: url, options: .atomic)
        try touch(key)
        try evict(protecting: key)
    }

    public func touch(_ key: String) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    public func totalBytes() throws -> Int64 {
        try entries().reduce(0) { $0 + $1.byteCount }
    }

    private func evict(protecting key: String) throws {
        let listed = try entries()
        let victims = ThumbnailDiskBudget.victims(
            entries: listed.filter { $0.key != key },
            incomingBytes: listed.first { $0.key == key }?.byteCount ?? 0,
            maxBytes: maxBytes
        )
        for victim in victims where victim != key {
            try? FileManager.default.removeItem(at: fileURL(for: victim))
        }
    }

    private func entries() throws -> [ThumbnailCacheEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let used = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            return ThumbnailCacheEntry(key: url.lastPathComponent, byteCount: size, lastUsed: used)
        }
    }

    private func safe(_ key: String) -> String {
        let filtered = key.lowercased().filter { $0.isHexDigit }
        if filtered.count == 64 { return filtered }
        let fallback = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        if fallback.isEmpty { return "thumb" }
        return String(fallback.prefix(80))
    }
}
