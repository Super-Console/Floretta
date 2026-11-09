import Foundation

/// Pixel size of an image. Zero on either axis means the size is unknown.
public struct ImagePixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var isUsable: Bool { width > 0 && height > 0 }

    public var longestEdge: Int { max(width, height) }
}

/// A rectangle in node-local points. Used for the image slot and the fitted image.
public struct ImageSlotRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var longestEdge: Double { max(width, height) }
}

/// The box a node reserves for one image. Drawing letterboxes inside it.
public enum ImageSlot {
    public static let maxWidth: Double = 160
    public static let maxHeight: Double = 96
    public static let topInset: Double = 6
    public static let horizontalInset: Double = 8
    public static let bottomGap: Double = 4

    public static func bandHeight(hasImage: Bool) -> Double {
        guard hasImage else { return 0 }
        return topInset + maxHeight + bottomGap
    }

    /// Slot at the top of a node, centered horizontally. Never wider than the node.
    public static func slot(nodeWidth: Double) -> ImageSlotRect {
        let available = max(0, nodeWidth - horizontalInset * 2)
        let width = min(maxWidth, available)
        let x = max(0, (nodeWidth - width) / 2)
        return ImageSlotRect(x: x, y: topInset, width: width, height: maxHeight)
    }
}

/// Scales an image uniformly so the whole picture stays inside the slot. No crop.
public enum ImageAspectFit {
    public static func fit(pixels: ImagePixelSize, in slot: ImageSlotRect) -> ImageSlotRect {
        guard pixels.isUsable, slot.width > 0, slot.height > 0 else {
            return ImageSlotRect(x: slot.x, y: slot.y, width: 0, height: 0)
        }
        let imageAspect = Double(pixels.width) / Double(pixels.height)
        let slotAspect = slot.width / slot.height
        let width: Double
        let height: Double
        if imageAspect > slotAspect {
            width = slot.width
            height = slot.width / imageAspect
        } else {
            height = slot.height
            width = slot.height * imageAspect
        }
        return ImageSlotRect(
            x: slot.x + (slot.width - width) / 2,
            y: slot.y + (slot.height - height) / 2,
            width: width,
            height: height
        )
    }
}

/// How many pixels an exported image needs so the page is not stretching a thumbnail.
public enum ImageExportResolution {
    /// Longest edge to ask ImageIO for. At least the fitted slot times `scale`
    /// when the source is that large, never larger than the source, and never above `cap`.
    public static func longestEdge(
        source: ImagePixelSize,
        slot: ImageSlotRect,
        scale: Double,
        cap: Int = 4096
    ) -> Int {
        let safeScale = (scale.isFinite && scale > 0) ? scale : 1
        let limit = max(1, cap)
        let fitted = source.isUsable ? ImageAspectFit.fit(pixels: source, in: slot) : slot
        let needed = Int((max(fitted.width, fitted.height) * safeScale).rounded(.up))
        let bounded = min(max(needed, 1), limit)
        guard source.isUsable else { return bounded }
        return min(bounded, max(1, source.longestEdge))
    }
}

/// The three ways a picture enters a node. They share one confirmation and one write path.
public enum ImageInsertEntry: String, Equatable, Sendable, CaseIterable {
    case filePicker
    case dragDrop
    case clipboardPaste
}

public struct ImageInsertPayload: Equatable, Sendable {
    public var entry: ImageInsertEntry
    public var filename: String
    public var byteCount: Int64

    public init(entry: ImageInsertEntry, filename: String, byteCount: Int64) {
        self.entry = entry
        self.filename = filename
        self.byteCount = byteCount
    }
}

public enum ImageInsertRoute {
    public static func accepts(filename: String) -> Bool {
        AttachmentKind.isImageExtension(AttachmentNames.fileExtension(of: filename))
    }

    /// Nil when the payload is not an image. Every entry otherwise builds the same proposal.
    public static func proposal(
        _ payload: ImageInsertPayload,
        currentDocumentByteCount: Int64
    ) -> AttachmentInsertProposal? {
        guard accepts(filename: payload.filename) else { return nil }
        return AttachmentInsertProposal(
            filename: payload.filename,
            fileByteCount: payload.byteCount,
            currentDocumentByteCount: currentDocumentByteCount
        )
    }
}

/// Extension to keep on a dropped or pasted image file. Path wins, then the UTI, then png.
public enum ImageFileName {
    public static func preferredExtension(pathExtension: String, typeExtension: String?) -> String {
        let fromPath = AttachmentNames.normalizeExtension(pathExtension)
        if AttachmentKind.isImageExtension(fromPath) { return fromPath }
        if let typeExtension {
            let fromType = AttachmentNames.normalizeExtension(typeExtension)
            if AttachmentKind.isImageExtension(fromType) { return fromType }
        }
        return "png"
    }
}

public enum ImageAttachments {
    public static func contains(_ document: MindMapDocument) -> Bool {
        func walk(_ nodes: [MindMapNode]) -> Bool {
            for node in nodes {
                if node.attachments.contains(where: { AttachmentKind.isImageExtension($0.fileExtension) }) {
                    return true
                }
                if walk(node.children) { return true }
            }
            return false
        }
        return walk(document.roots)
    }
}

/// What to decode, and whether the bytes belong in the 256px disk LRU.
public struct ImageDecodePlan: Equatable, Sendable {
    public var hash: String
    public var longestEdge: Int
    /// Viewport thumbnails go through `ThumbnailFileCache`. Export frames do not.
    public var storesInThumbnailCache: Bool

    public init(hash: String, longestEdge: Int, storesInThumbnailCache: Bool) {
        self.hash = hash
        self.longestEdge = longestEdge
        self.storesInThumbnailCache = storesInThumbnailCache
    }
}

public enum ImageDecodePlanKind {
    public static func thumbnail(hash: String) -> ImageDecodePlan {
        ImageDecodePlan(
            hash: hash,
            longestEdge: StreamingBudget.thumbnailLongestEdge,
            storesInThumbnailCache: true
        )
    }

    public static func export(
        hash: String,
        source: ImagePixelSize,
        slot: ImageSlotRect,
        scale: Double
    ) -> ImageDecodePlan {
        ImageDecodePlan(
            hash: hash,
            longestEdge: ImageExportResolution.longestEdge(source: source, slot: slot, scale: scale),
            storesInThumbnailCache: false
        )
    }
}

/// Hands decode work to `runner`. This function does not call `body`.
public enum ImageDecodeScheduler {
    public static func submit(
        runner: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
        body: @escaping @Sendable () -> Void
    ) {
        runner(body)
    }
}

/// Background lane used by the canvas. The body is queued, not run on the caller.
public enum ImageDecodeLane {
    public static func detached(_ body: @escaping @Sendable () -> Void) {
        Task.detached(priority: .utility) {
            body()
        }
    }
}
