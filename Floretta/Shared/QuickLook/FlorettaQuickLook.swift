import CoreGraphics
import CoreText
import FlorettaCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FlorettaQuickLookPicture: Equatable, Sendable {
    var png: Data
    var pixelSize: CGSize
    var pointSize: CGSize
    var visibleNodeIDs: [UUID]
    var truncated: Bool
    /// Set when the file could not be drawn and the PNG is the localized fallback card.
    var caption: String?
}

struct FlorettaQuickLookPreview: Equatable, Sendable {
    var data: Data
    var contentSize: CGSize
    var contentTypeIdentifier: String
}

/// Finder thumbnail and Quick Look preview for one `.floretta`.
///
/// Opens through `FlorettaStreamingDocument` (central directory plus the two JSON entries).
/// Draws through `MapExporter`, the same picture as PNG export, fitted to the requested edge.
/// Image nodes reuse `ThumbnailPipeline.decodeSpilled` and `ImageIOThumbnailDecoder` at the
/// thumbnail edge. Attachment bodies larger than `stagedAttachmentByteCeiling` are not copied.
@MainActor
enum FlorettaQuickLookRenderer {
    nonisolated static let fallbackKey = "无法生成缩略图。"
    /// Longest pixel edge when the caller does not name one. A large Finder icon, not an export page.
    nonisolated static let longestPixelEdge: CGFloat = 512
    /// Spacebar preview. One bitmap, longest edge capped here.
    nonisolated static let finderPreviewEdge: CGFloat = 1024
    nonisolated static let maximumPixelEdge: CGFloat = 1024
    /// Same ceiling as `StreamingBudget.writePeakBytes`. A 10GB asset is not staged into temp.
    nonisolated static let stagedAttachmentByteCeiling = Int64(StreamingBudget.writePeakBytes)

    nonisolated static func pixelEdge(points: CGSize, scale: CGFloat) -> CGFloat {
        let longest = max(points.width, points.height)
        let screen = scale.isFinite && scale > 0 ? scale : 1
        let pixels = longest.isFinite && longest > 0 ? longest * screen : longestPixelEdge
        let edge = pixels.isFinite && pixels > 0 ? pixels : longestPixelEdge
        return min(max(edge, 16), maximumPixelEdge)
    }

    static func picture(
        at url: URL,
        longestPixelEdge requested: CGFloat = FlorettaQuickLookRenderer.longestPixelEdge,
        files: any StreamingFilePort = FoundationStreamingFiles(),
        locale: Locale = .current,
        stagedAttachmentByteCeiling ceiling: Int64 = FlorettaQuickLookRenderer.stagedAttachmentByteCeiling
    ) -> FlorettaQuickLookPicture {
        let edge = min(max(requested.isFinite ? requested : longestPixelEdge, 16), maximumPixelEdge)
        do {
            let opened = try load(url, files: files)
            let images = nodeImages(
                document: opened.document,
                entries: opened.entries,
                archive: url,
                files: files,
                ceiling: ceiling
            )
            let options = MapExportOptions(
                scale: .one,
                background: .white,
                padding: 32,
                fitLongestPixelEdge: edge
            )
            let rendered = MapExporter.png(document: opened.document, options: options, images: images)
            if let png = rendered.png, !png.isEmpty, rendered.pixelSize.width > 1, rendered.pixelSize.height > 1 {
                return FlorettaQuickLookPicture(
                    png: png,
                    pixelSize: rendered.pixelSize,
                    pointSize: rendered.pointSize,
                    visibleNodeIDs: rendered.visibleNodeIDs,
                    truncated: rendered.truncated,
                    caption: nil
                )
            }
        } catch {
            return fallback(edge: edge, locale: locale)
        }
        return fallback(edge: edge, locale: locale)
    }

    nonisolated static func preview(from picture: FlorettaQuickLookPicture) -> FlorettaQuickLookPreview {
        FlorettaQuickLookPreview(
            data: picture.png,
            contentSize: picture.pixelSize,
            contentTypeIdentifier: UTType.png.identifier
        )
    }

    nonisolated static func writePNG(_ picture: FlorettaQuickLookPicture, in directory: URL) throws -> URL {
        guard !picture.png.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("floretta-ql-\(UUID().uuidString).png")
        try picture.png.write(to: url, options: .atomic)
        return url
    }

    private struct Opened {
        var document: MindMapDocument
        var entries: [ZipStoredEntry]
    }

    private static func load(_ url: URL, files: any StreamingFilePort) throws -> Opened {
        if try files.isZip(at: url) {
            let reader = try files.openReader(at: url)
            defer { try? reader.close() }
            let opened = try FlorettaStreamingDocument.open(reader)
            return Opened(document: opened.document, entries: opened.directory.attachments)
        }
        let reader = try files.openReader(at: url)
        defer { try? reader.close() }
        let data = try readLegacy(reader)
        let loaded = try FlorettaDocumentFile.read(data: data)
        return Opened(document: loaded.package.document, entries: [])
    }

    /// Plain JSON `.floretta` files are the document itself. Stop at the open budget.
    private static func readLegacy(_ reader: RandomAccessReader) throws -> Data {
        let limit = Int64(StreamingBudget.openRamDeltaBytes)
        if reader.count > limit {
            throw DocumentContainerError.overLimit("Legacy file exceeds the open budget.")
        }
        let chunk = StreamingBudget.chunkBytes
        var data = Data()
        data.reserveCapacity(Int(max(reader.count, 0)))
        var offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: chunk)
        while offset < reader.count {
            let count = try buffer.withUnsafeMutableBytes { raw in
                try reader.read(at: offset, into: raw)
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            offset += Int64(count)
        }
        return data
    }

    private static func nodeImages(
        document: MindMapDocument,
        entries: [ZipStoredEntry],
        archive: URL,
        files: any StreamingFilePort,
        ceiling: Int64
    ) -> [String: CGImage] {
        let needed = Set(MapExporter.visibleFrames(in: document).flatMap(\.thumbnailHashes))
        guard !needed.isEmpty else { return [:] }
        let spill = FileManager.default.temporaryDirectory
            .appendingPathComponent("floretta-ql-spill-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: spill, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: spill) }
        var decoded: [String: CGImage] = [:]
        let decoder = ImageIOThumbnailDecoder()
        for entry in entries {
            guard let hash = entry.sha256, needed.contains(hash), decoded[hash] == nil else { continue }
            guard let ext = AttachmentNames.parseAsset(entry.name)?.fileExtension,
                  AttachmentKind.isImageExtension(ext) else { continue }
            if ceiling >= 0, entry.byteCount > UInt64(ceiling) { continue }
            guard let data = try? ThumbnailPipeline.decodeSpilled(
                entry: entry,
                archiveURL: archive,
                spillDirectory: spill,
                files: files,
                longestEdge: { _ in StreamingBudget.thumbnailLongestEdge },
                decoder: decoder
            ), let image = ImageIOThumbnailDecoder.image(from: data) else { continue }
            decoded[hash] = image
        }
        return decoded
    }

    private static func fallback(edge: CGFloat, locale: Locale) -> FlorettaQuickLookPicture {
        let caption = FlorettaL10n.string(fallbackKey, locale: locale)
        let side = Int(min(max(edge, 16), maximumPixelEdge).rounded(.down))
        let size = CGSize(width: side, height: side)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return FlorettaQuickLookPicture(
                png: Data(), pixelSize: size, pointSize: size,
                visibleNodeIDs: [], truncated: false, caption: caption
            )
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, min(18, CGFloat(side) / 12), nil)
        let ink = CGColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: ink,
        ]
        if let attributed = CFAttributedStringCreate(nil, caption as CFString, attributes as CFDictionary) {
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, [])
            context.textPosition = CGPoint(
                x: max(8, (CGFloat(side) - bounds.width) / 2),
                y: (CGFloat(side) - bounds.height) / 2
            )
            CTLineDraw(line, context)
        }
        let image = context.makeImage()
        let png = image.flatMap(pngData) ?? Data()
        let pixel = image.map { CGSize(width: $0.width, height: $0.height) } ?? size
        return FlorettaQuickLookPicture(
            png: png,
            pixelSize: pixel,
            pointSize: pixel,
            visibleNodeIDs: [],
            truncated: false,
            caption: caption
        )
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
