import Foundation

/// What the platform learned about a file before any byte of it is read.
public struct FileTypeFact: Equatable, Sendable {
    public var typeIdentifier: String?
    /// True when the system has a type icon that is not the generic document icon.
    public var systemIconAvailable: Bool
    public var fileExtension: String

    public init(typeIdentifier: String?, systemIconAvailable: Bool, fileExtension: String) {
        self.typeIdentifier = typeIdentifier
        self.systemIconAvailable = systemIconAvailable
        self.fileExtension = AttachmentNames.normalizeExtension(fileExtension)
    }
}

/// Which icon to draw. `generic` is the fallback when the system has none.
public enum FileIconResolution: Equatable, Sendable {
    case system(typeIdentifier: String)
    case generic(typeIdentifier: String?)
}

public enum FileIconPolicy {
    public static func resolution(for fact: FileTypeFact) -> FileIconResolution {
        if fact.systemIconAvailable,
           let identifier = fact.typeIdentifier,
           !identifier.isEmpty,
           !identifier.hasPrefix("dyn.") {
            return .system(typeIdentifier: identifier)
        }
        return .generic(typeIdentifier: fact.typeIdentifier)
    }
}

/// Any file the user picked, including PSD, PDF, and DMG. Pictures stay on the image slot.
public enum FileAttachmentRoute {
    public static func accepts(filename: String, isDirectory: Bool = false) -> Bool {
        if isDirectory { return false }
        let name = (filename as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { return false }
        return true
    }

    /// Same confirmation as every other attachment: this file's size and the projected document size.
    public static func proposal(
        filename: String,
        byteCount: Int64,
        currentDocumentByteCount: Int64,
        isDirectory: Bool = false
    ) -> AttachmentInsertProposal? {
        guard accepts(filename: filename, isDirectory: isDirectory) else { return nil }
        return AttachmentInsertProposal(
            filename: filename,
            fileByteCount: byteCount,
            currentDocumentByteCount: currentDocumentByteCount
        )
    }
}

public enum FileAttachmentName {
    /// Keep a real extension. When the filename has none, use the one UTType recognized.
    public static func storedFilename(original: String, recognizedExtension: String) -> String {
        let base = (original as NSString).lastPathComponent
        guard !base.isEmpty else {
            return "文件.\(AttachmentNames.normalizeExtension(recognizedExtension))"
        }
        if !(base as NSString).pathExtension.isEmpty { return base }
        let recognized = AttachmentNames.normalizeExtension(recognizedExtension)
        if recognized == "bin" { return base }
        return "\(base).\(recognized)"
    }
}

public enum FileBadgeMetrics {
    public static let rowHeight: Double = 28
    public static let iconSide: Double = 16
    public static let gap: Double = 4
    public static let horizontalInset: Double = 8
    public static let topGap: Double = 4
    public static let bottomGap: Double = 4

    public static func bandHeight(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return topGap + Double(count) * rowHeight + bottomGap
    }
}

/// One non-image attachment drawn on a node: type icon, filename, size.
public struct FileBadge: Equatable, Sendable {
    public var sha256: String
    public var filename: String
    public var fileExtension: String
    public var byteCount: Int64
    public var sizeLabel: String
    /// Node-local row.
    public var row: ImageSlotRect
    /// Node-local icon box, inside `row`.
    public var icon: ImageSlotRect

    public init(
        sha256: String,
        filename: String,
        fileExtension: String,
        byteCount: Int64,
        sizeLabel: String,
        row: ImageSlotRect,
        icon: ImageSlotRect
    ) {
        self.sha256 = sha256
        self.filename = filename
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.sizeLabel = sizeLabel
        self.row = row
        self.icon = icon
    }

    public var line: String { "\(filename) \(sizeLabel)" }
}

public enum FileBadgeLayout {
    public static func fileAttachments(in node: MindMapNode) -> [NodeAttachment] {
        node.attachments.filter { !AttachmentKind.isImageExtension($0.fileExtension) }
    }

    public static func badges(
        attachments: [NodeAttachment],
        nodeWidth: Double,
        nodeHeight: Double
    ) -> [FileBadge] {
        let files = attachments.filter { !AttachmentKind.isImageExtension($0.fileExtension) }
        let band = FileBadgeMetrics.bandHeight(count: files.count)
        guard band > 0, nodeWidth > 0, nodeHeight > 0 else { return [] }
        let rowWidth = max(0, nodeWidth - FileBadgeMetrics.horizontalInset * 2)
        let top = nodeHeight - band + FileBadgeMetrics.topGap
        return files.enumerated().map { index, attachment in
            let y = top + Double(index) * FileBadgeMetrics.rowHeight
            let row = ImageSlotRect(
                x: FileBadgeMetrics.horizontalInset,
                y: y,
                width: rowWidth,
                height: FileBadgeMetrics.rowHeight
            )
            let side = min(FileBadgeMetrics.iconSide, max(0, row.height - 4))
            let icon = ImageSlotRect(
                x: row.x,
                y: row.y + (row.height - side) / 2,
                width: side,
                height: side
            )
            return FileBadge(
                sha256: attachment.sha256,
                filename: attachment.filename,
                fileExtension: attachment.fileExtension,
                byteCount: attachment.byteCount,
                sizeLabel: AttachmentByteFormat.label(attachment.byteCount),
                row: row,
                icon: icon
            )
        }
    }
}

public enum FileBadgeHit {
    public static func badge(canvasX: Double, canvasY: Double, in frame: NodeFrame) -> FileBadge? {
        let localX = canvasX - Double(frame.origin.x)
        let localY = canvasY - Double(frame.origin.y)
        return frame.fileBadges.first { contains($0.row, x: localX, y: localY) }
    }

    private static func contains(_ row: ImageSlotRect, x: Double, y: Double) -> Bool {
        x >= row.x && y >= row.y && x <= row.x + row.width && y <= row.y + row.height
    }
}

/// Title drawn in the node. File rows are badges, so they are left out of the centered text.
public enum NodeAttachmentDrawing {
    public static func measuredText(_ node: MindMapNode) -> String {
        let imageLines = node.attachments
            .filter { AttachmentKind.isImageExtension($0.fileExtension) }
            .map { "\($0.filename) \(AttachmentByteFormat.label($0.byteCount))" }
        if imageLines.isEmpty { return node.text }
        return node.text + "\n" + imageLines.joined(separator: "\n")
    }

    public static func canvasText(title: String, caption: String, fileBadges: [FileBadge]) -> String {
        guard !fileBadges.isEmpty else {
            return caption.isEmpty ? title : title + "\n" + caption
        }
        let hidden = Set(fileBadges.map(\.line))
        let kept = caption
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty && !hidden.contains($0) }
        if kept.isEmpty { return title }
        return title + "\n" + kept.joined(separator: "\n")
    }
}

public struct FilePreviewTicket: Equatable, Sendable {
    public var nodeID: UUID
    public var sha256: String
    public var filename: String
    public var previewPath: String

    public init(nodeID: UUID, sha256: String, filename: String, previewPath: String) {
        self.nodeID = nodeID
        self.sha256 = sha256
        self.filename = filename
        self.previewPath = previewPath
    }
}

public enum FilePreviewPhase: Equatable, Sendable {
    case idle
    case presenting(FilePreviewTicket)
    case alert(String)

    public var previewPath: String? {
        if case .presenting(let ticket) = self { return ticket.previewPath }
        return nil
    }

    public var ticket: FilePreviewTicket? {
        if case .presenting(let ticket) = self { return ticket }
        return nil
    }

    public var alertMessage: String? {
        if case .alert(let message) = self { return message }
        return nil
    }
}

/// QuickLook stays up only while the spilled file is still on disk.
public enum FilePreviewSession {
    public static let missingMessage = "这个文件已经不在，预览已关闭。"
    public static let unavailableMessage = "无法打开预览。"

    public static func begin(_ ticket: FilePreviewTicket, fileExists: Bool) -> FilePreviewPhase {
        guard fileExists, !ticket.previewPath.isEmpty else { return .alert(missingMessage) }
        return .presenting(ticket)
    }

    /// The preview surface noticed the file is gone. Does not trap.
    public static func fileDisappeared(_ phase: FilePreviewPhase) -> FilePreviewPhase {
        guard case .presenting = phase else { return phase }
        return .alert(missingMessage)
    }

    public static func unavailable() -> FilePreviewPhase {
        .alert(unavailableMessage)
    }

    public static func userClosed(_ phase: FilePreviewPhase) -> FilePreviewPhase {
        guard case .presenting = phase else { return phase }
        return .idle
    }

    public static func dismissAlert(_ phase: FilePreviewPhase) -> FilePreviewPhase {
        guard case .alert = phase else { return phase }
        return .idle
    }
}

/// Streams one stored attachment to `destination`. Returns no bytes.
public enum FilePreviewSpill {
    public static func write(
        entry: ZipStoredEntry,
        archiveURL: URL,
        to destination: URL,
        files: any StreamingFilePort
    ) throws {
        guard entry.method == 0 else {
            throw DocumentContainerError.corrupt("Attachment \(entry.name) is compressed.")
        }
        let reader = try files.openReader(at: archiveURL)
        let writer = try files.openWriter(at: destination)
        do {
            try FlorettaStreamingDocument.exportAttachment(entry, from: reader, to: writer)
            try writer.close()
            try reader.close()
        } catch {
            try? writer.close()
            try? reader.close()
            try? files.remove(at: destination)
            throw error
        }
    }
}
