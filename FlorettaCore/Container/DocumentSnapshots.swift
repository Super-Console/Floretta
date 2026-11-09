import Foundation

/// How many previous `document.json` copies to keep beside a `.floretta` file.
/// `limit == 0` keeps none and does not pin attachment bytes. The hard cap is 32.
public struct SnapshotRetention: Equatable, Sendable {
    public static let standard = SnapshotRetention(limit: 8)
    public static let none = SnapshotRetention(limit: 0)
    public static let hardCap = 32

    public var limit: Int

    public init(limit: Int) {
        if limit <= 0 {
            self.limit = 0
        } else {
            self.limit = min(limit, Self.hardCap)
        }
    }
}

/// One stored copy of `document.json`. Attachments are not copied.
public struct DocumentSnapshot: Equatable, Sendable {
    public var generation: Int
    public var document: MindMapDocument

    public init(generation: Int, document: MindMapDocument) {
        self.generation = generation
        self.document = document
    }
}

struct StagedSnapshots {
    var retainHashes: Set<String>
    var obsolete: [URL]
}

/// Sidecar history: `.<filename>.snapshots/00000001.json` holds full `document.json` bytes.
/// The user file stays `formatVersion` 1. Old packages with no sidecar still open.
public enum DocumentSnapshots {
    public static func directory(for documentURL: URL) -> URL {
        let name = documentURL.lastPathComponent
        return documentURL.deletingLastPathComponent()
            .appendingPathComponent(".\(name).snapshots", isDirectory: true)
    }

    /// Oldest first.
    public static func list(documentAt url: URL) throws -> [DocumentSnapshot] {
        try load(documentAt: url).map { DocumentSnapshot(generation: $0.generation, document: $0.document) }
    }

    /// Writes `generation` back into `url` through the normal atomic save.
    /// The document that was current becomes the newest snapshot, so the rollback can itself be undone.
    @discardableResult
    public static func rollback(
        documentAt url: URL,
        to generation: Int,
        files: any StreamingFilePort,
        retention: SnapshotRetention = .standard
    ) throws -> MindMapDocument {
        guard let snapshot = try list(documentAt: url).first(where: { $0.generation == generation }) else {
            throw DocumentContainerError.missingEntry("snapshot \(generation)")
        }
        _ = try FlorettaStreamingDocument.save(
            document: snapshot.document,
            to: url,
            files: files,
            snapshots: retention
        )
        return snapshot.document
    }

    static func stage(
        previous documentJSON: Data,
        for url: URL,
        retention: SnapshotRetention
    ) throws -> StagedSnapshots {
        guard retention.limit > 0 else {
            return StagedSnapshots(retainHashes: [], obsolete: [])
        }
        var stored = try load(documentAt: url)
        if stored.last?.bytes != documentJSON {
            let next = (stored.last?.generation ?? 0) + 1
            let folder = directory(for: url)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(String(format: "%08d.json", next))
            try AtomicFileBytes.write(documentJSON, to: file)
            let document = try FlorettaCodec.decode(documentJSON)
            stored.append(StoredSnapshot(generation: next, url: file, bytes: documentJSON, document: document))
        }
        var obsolete: [URL] = []
        while stored.count > retention.limit {
            obsolete.append(stored.removeFirst().url)
        }
        var hashes: Set<String> = []
        for snapshot in stored {
            hashes.formUnion(AttachmentReferences.hashes(in: snapshot.document))
        }
        return StagedSnapshots(retainHashes: hashes, obsolete: obsolete)
    }

    static func discard(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private struct StoredSnapshot {
        var generation: Int
        var url: URL
        var bytes: Data
        var document: MindMapDocument
    }

    private static func load(documentAt url: URL) throws -> [StoredSnapshot] {
        let folder = directory(for: url)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var stored: [StoredSnapshot] = []
        for name in names {
            guard name.hasSuffix(".json") else { continue }
            let stem = String(name.dropLast(".json".count))
            guard let generation = Int(stem), stem.allSatisfy(\.isNumber) else { continue }
            let file = folder.appendingPathComponent(name)
            let count = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if count > StreamingBudget.maxMaterializedOpenBytes { continue }
            let bytes = try Data(contentsOf: file)
            guard let document = try? FlorettaCodec.decode(bytes) else { continue }
            stored.append(StoredSnapshot(generation: generation, url: file, bytes: bytes, document: document))
        }
        stored.sort { $0.generation < $1.generation }
        return stored
    }
}

/// A save that stopped before `rename`. The partial sibling is not a user file.
public struct InterruptedSave: Equatable, Sendable {
    public var documentURL: URL
    public var partialURL: URL
    public var canRestorePrevious: Bool
    public var promptTitle: String
    public var promptMessage: String

    public init(
        documentURL: URL,
        partialURL: URL,
        canRestorePrevious: Bool,
        promptTitle: String,
        promptMessage: String
    ) {
        self.documentURL = documentURL
        self.partialURL = partialURL
        self.canRestorePrevious = canRestorePrevious
        self.promptTitle = promptTitle
        self.promptMessage = promptMessage
    }
}

public enum SaveRecovery {
    /// Non-nil when `.<name>.partial` is still beside the document.
    public static func inspect(documentAt url: URL, files: any StreamingFilePort) -> InterruptedSave? {
        let partial = AtomicFileBytes.partialURL(for: url)
        guard files.fileExists(at: partial) else { return nil }
        let destIntact = files.fileExists(at: url) && ((try? files.isZip(at: url)) == true)
        let snapshotAvailable = ((try? DocumentSnapshots.list(documentAt: url).isEmpty) == false)
        let canRestore = destIntact || snapshotAvailable
        let message: String
        if destIntact {
            message = "上次写入中断了，没有替换已经保存的导图。恢复上一版会丢掉未完成的半截文件，留下上一个完整版本。"
        } else if snapshotAvailable {
            message = "上次写入中断了，当前文件打不开。可以恢复快照里的上一版。只存在于损坏文件里的附件，打开时会按文件名指出。"
        } else {
            message = "上次写入中断了，没有可恢复的上一版。未完成的半截文件会被丢掉。"
        }
        return InterruptedSave(
            documentURL: url,
            partialURL: partial,
            canRestorePrevious: canRestore,
            promptTitle: "保存未完成",
            promptMessage: message
        )
    }

    public static func discardPartial(documentAt url: URL, files: any StreamingFilePort) throws {
        let partial = AtomicFileBytes.partialURL(for: url)
        guard files.fileExists(at: partial) else { return }
        try files.remove(at: partial)
    }

    /// Prefers the destination when it is still a zip (the rename never happened).
    /// Otherwise writes the newest `document.json` snapshot back with an atomic save.
    @discardableResult
    public static func restorePrevious(
        documentAt url: URL,
        files: any StreamingFilePort,
        retention: SnapshotRetention = .standard
    ) throws -> MindMapDocument {
        if files.fileExists(at: url), (try? files.isZip(at: url)) == true {
            let reader = try files.openReader(at: url)
            let opened = try FlorettaStreamingDocument.open(reader)
            try reader.close()
            try discardPartial(documentAt: url, files: files)
            return opened.document
        }
        let snapshots = try DocumentSnapshots.list(documentAt: url)
        guard let newest = snapshots.max(by: { $0.generation < $1.generation }) else {
            throw DocumentContainerError.corrupt("没有可恢复的上一版。")
        }
        if files.fileExists(at: url) {
            try files.remove(at: url)
        }
        try discardPartial(documentAt: url, files: files)
        _ = try FlorettaStreamingDocument.save(
            document: newest.document,
            to: url,
            files: files,
            snapshots: retention
        )
        return newest.document
    }
}
