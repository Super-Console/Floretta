import FlorettaCore
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum MapExportScale: CGFloat, Equatable, Sendable {
    /// 1 render pixel per logical point. No extra scale coefficient.
    case one = 1
    case two = 2
    case three = 3
}

enum MapExportBackground: Equatable, Sendable {
    case white
    case transparent
}

struct MapExportOptions: Equatable, Sendable {
    var scale: MapExportScale = .two
    var background: MapExportBackground = .white
    /// Canvas points added on every side of the node bounds.
    var padding: CGFloat = 32
    /// Longest PNG edge, in pixels. Larger maps are clipped, not drawn at full size.
    var maxPixelDimension: CGFloat = 8192
    /// User choice for PNG and PDF. On by default so the control is available and the picture matches the canvas.
    var includeStickies: Bool = true
    /// When set, the whole padded map is drawn and the longest pixel edge stays at most this value.
    /// Nil keeps the export clip at `maxPixelDimension`. Quick Look sets this so Finder sees the map, not a corner.
    var fitLongestPixelEdge: CGFloat? = nil
}

struct MapExportResult: Equatable, Sendable {
    var png: Data?
    var pdf: Data?
    var pointSize: CGSize
    var pixelSize: CGSize
    var mediaBox: CGRect
    var renderBounds: CGRect
    var truncated: Bool
    var notice: String?
    var visibleNodeIDs: [UUID]
}

/// PNG and PDF of the current map through SwiftUI `ImageRenderer`.
/// The picture is the nodes, hierarchy links, relationship lines, summary brackets,
/// boundary enclosures, and — when the user leaves the option on — sticky cards.
/// No toolbar, sidebar, grid, or selection.
@MainActor
enum MapExporter {
    static let clippingNotice = "导出已按最大尺寸裁切，超出的内容没有画进文件。"
    static let emptyNotice = "没有可导出的节点。"

    static func visibleFrames(in document: MindMapDocument, scheme: MapColorScheme = .light) -> [NodeFrame] {
        CanvasPlacement.nodes(in: document, scheme: scheme)
    }

    static func png(
        document: MindMapDocument,
        options: MapExportOptions = MapExportOptions(),
        images: [String: CGImage] = [:],
        scheme: MapColorScheme = .light
    ) -> MapExportResult {
        // PNG holds one canvas: the active sheet. Other sheets stay on the native document.
        let document = document.singleTreeExport()
        let plan = plan(document: document, options: options, scheme: scheme)
        guard plan.pointSize.width > 1, plan.pointSize.height > 1 else {
            return empty(plan)
        }
        let renderer = makeRenderer(plan: plan, options: options, document: document, images: images, scheme: scheme)
        guard let image = renderer.cgImage else {
            return failed(plan)
        }
        return MapExportResult(
            png: pngData(image),
            pdf: nil,
            pointSize: plan.pointSize,
            pixelSize: CGSize(width: image.width, height: image.height),
            mediaBox: .zero,
            renderBounds: plan.renderBounds,
            truncated: plan.truncated,
            notice: plan.notice,
            visibleNodeIDs: plan.visibleNodeIDs
        )
    }

    static func pdf(
        document: MindMapDocument,
        options: MapExportOptions = MapExportOptions(),
        images: [String: CGImage] = [:],
        scheme: MapColorScheme = .light
    ) -> MapExportResult {
        // PDF holds one canvas: the active sheet. Other sheets stay on the native document.
        let document = document.singleTreeExport()
        let plan = plan(document: document, options: options, scheme: scheme)
        guard plan.pointSize.width > 1, plan.pointSize.height > 1 else {
            return empty(plan)
        }
        let renderer = makeRenderer(plan: plan, options: options, document: document, images: images, scheme: scheme)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            return failed(plan)
        }
        var media = CGRect.zero
        renderer.render { size, draw in
            media = CGRect(origin: .zero, size: size)
            var box = media
            guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return MapExportResult(
            png: nil,
            pdf: data as Data,
            pointSize: plan.pointSize,
            pixelSize: .zero,
            mediaBox: media,
            renderBounds: plan.renderBounds,
            truncated: plan.truncated,
            notice: plan.notice,
            visibleNodeIDs: plan.visibleNodeIDs
        )
    }

    private struct Plan {
        var renderBounds: CGRect
        var pointSize: CGSize
        var pixelScale: CGFloat
        var truncated: Bool
        var notice: String?
        var visibleNodeIDs: [UUID]
    }

    private static func plan(document: MindMapDocument, options: MapExportOptions, scheme: MapColorScheme) -> Plan {
        let frames = visibleFrames(in: document, scheme: scheme)
        let ids = frames.map(\.id)
        guard let content = CanvasPlacement.contentBounds(
            in: document,
            includingStickies: options.includeStickies
        ),
              content.width > 0, content.height > 0 else {
            return Plan(
                renderBounds: .zero,
                pointSize: .zero,
                pixelScale: 1,
                truncated: false,
                notice: emptyNotice,
                visibleNodeIDs: ids
            )
        }
        let pad = max(options.padding, 0)
        let padded = content.insetBy(dx: -pad, dy: -pad)
        if let fit = options.fitLongestPixelEdge, fit.isFinite, fit > 1 {
            let longest = max(padded.width, padded.height, 1)
            let scale = min(1, fit / longest)
            return Plan(
                renderBounds: padded,
                pointSize: padded.size,
                pixelScale: scale,
                truncated: false,
                notice: nil,
                visibleNodeIDs: ids
            )
        }
        let scale = max(options.scale.rawValue, 1)
        let cap = max(options.maxPixelDimension, 1)
        let maxPoints = cap / scale
        var render = padded
        var truncated = false
        if padded.width > maxPoints || padded.height > maxPoints {
            truncated = true
            render.size.width = min(padded.width, maxPoints)
            render.size.height = min(padded.height, maxPoints)
        }
        return Plan(
            renderBounds: render,
            pointSize: render.size,
            pixelScale: scale,
            truncated: truncated,
            notice: truncated ? clippingNotice : nil,
            visibleNodeIDs: ids
        )
    }

    private static func makeRenderer(
        plan: Plan,
        options: MapExportOptions,
        document: MindMapDocument,
        images: [String: CGImage],
        scheme: MapColorScheme
    ) -> ImageRenderer<MapExportView> {
        let frames = visibleFrames(in: document, scheme: scheme)
        let appearance = MapThemeCatalog.appearance(
            themeID: document.themeID,
            scheme: scheme,
            fallback: .standard
        )
        let paper = exportPaper(options.background, canvas: appearance.canvasBackground)
        let view = MapExportView(
            frames: frames,
            lines: RelationshipGeometry.lines(for: document.relationships, frames: frames),
            summaries: SummaryGeometry.summaries(in: document, frames: frames),
            boundaries: SummaryGeometry.boundaries(in: document, frames: frames),
            stickies: document.stickiesForPictureExport(included: options.includeStickies),
            regions: document.regions,
            renderBounds: plan.renderBounds,
            paper: paper.color,
            images: images
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = plan.pixelScale
        renderer.isOpaque = paper.opaque
        renderer.proposedSize = ProposedViewSize(width: plan.pointSize.width, height: plan.pointSize.height)
        return renderer
    }

    private static func empty(_ plan: Plan) -> MapExportResult {
        MapExportResult(
            png: nil, pdf: nil, pointSize: .zero, pixelSize: .zero, mediaBox: .zero,
            renderBounds: plan.renderBounds, truncated: false, notice: plan.notice,
            visibleNodeIDs: plan.visibleNodeIDs
        )
    }

    private static func failed(_ plan: Plan) -> MapExportResult {
        MapExportResult(
            png: nil, pdf: nil, pointSize: plan.pointSize, pixelSize: .zero, mediaBox: .zero,
            renderBounds: plan.renderBounds, truncated: plan.truncated, notice: plan.notice,
            visibleNodeIDs: plan.visibleNodeIDs
        )
    }

    private static func exportPaper(
        _ background: MapExportBackground,
        canvas: BranchColor?
    ) -> (color: Color, opaque: Bool) {
        switch background {
        case .transparent:
            return (.clear, false)
        case .white:
            if let canvas {
                return (Color(red: canvas.red, green: canvas.green, blue: canvas.blue), true)
            }
            return (.white, true)
        }
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

/// Nodes, hierarchy links, relationship lines, summaries, and boundaries. No chrome.
private struct MapExportView: View {
    var frames: [NodeFrame]
    var lines: [RelationshipLine]
    var summaries: [SummaryMark]
    var boundaries: [BoundaryMark]
    var stickies: [StickyNote]
    var regions: [CanvasRegion]
    var renderBounds: CGRect
    var paper: Color
    var images: [String: CGImage]

    var body: some View {
        Canvas { context, _ in
            for region in regions {
                let rect = local(region.bounds)
                guard rect.width > 1, rect.height > 1 else { continue }
                let path: Path
                switch region.shape {
                case .rectangle:
                    path = Path(roundedRect: rect, cornerRadius: min(10, rect.height / 6))
                case .ellipse:
                    path = Path(ellipseIn: rect)
                }
                context.fill(path, with: .color(color(region.fill)))
                if region.strokeWidth > 0 {
                    context.stroke(path, with: .color(color(region.border)), lineWidth: CGFloat(region.strokeWidth))
                }
                if !region.label.isEmpty {
                    let band = CGRect(x: rect.minX + 12, y: rect.minY + 8, width: max(0, rect.width - 24), height: min(22, max(0, rect.height - 16)))
                    if band.width > 1, band.height > 1 {
                        var layer = context
                        layer.clip(to: path)
                        layer.draw(Text(region.label).font(.system(size: 14)), in: band)
                    }
                }
            }
            for mark in boundaries {
                let rect = local(mark.rect)
                let path = Path(roundedRect: rect, cornerRadius: SummaryGeometry.cornerRadius)
                let ink = color(SummaryGeometry.boundaryInk)
                context.fill(path, with: .color(ink.opacity(0.08)))
                context.stroke(path, with: .color(ink), lineWidth: SummaryGeometry.lineWidth)
                if !mark.title.isEmpty {
                    let title = local(mark.titleRect)
                    if title.width > 1, title.height > 1 {
                        context.fill(Path(roundedRect: title, cornerRadius: 4), with: .color(.white))
                        context.draw(
                            Text(mark.title).font(.system(size: SummaryGeometry.titleFontSize)),
                            in: title.insetBy(dx: 4, dy: 1)
                        )
                    }
                }
            }
            for node in frames {
                guard let link = node.link else { continue }
                let drawn = ThemeCurvePath.make(link: link, straight: false) { local($0) }
                let ink = color(link.color)
                if drawn.tapered {
                    context.fill(drawn.path, with: .color(ink))
                } else {
                    context.stroke(drawn.path, with: .color(ink), lineWidth: link.lineWidth)
                }
            }
            for line in lines {
                stroke(line, in: context)
            }
            for node in frames {
                let rect = local(node.frame)
                let path = Path(roundedRect: rect, cornerRadius: node.cornerRadius)
                context.fill(path, with: .color(color(node.fill)))
                if node.borderWidth > 0 {
                    context.stroke(path, with: .color(color(node.border)), lineWidth: node.borderWidth)
                }
                var textRect = rect.insetBy(dx: 8, dy: 4)
                if let hash = node.thumbnailHashes.first, let image = images[hash] {
                    let imageRect = ImagePlacement.rect(for: image, in: rect)
                    context.draw(Image(decorative: image, scale: 1), in: imageRect)
                    let top = imageRect.maxY + 2
                    textRect = CGRect(
                        x: rect.minX + 8,
                        y: top,
                        width: max(0, rect.width - 16),
                        height: max(0, rect.maxY - top - 4)
                    )
                }
                if node.tagBandHeight > 0 {
                    let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: node.fileBadges.count))
                    let tagTop = rect.maxY - fileBand - node.tagBandHeight
                    textRect.size.height = max(0, min(textRect.maxY, tagTop - 2) - textRect.minY)
                }
                textRect = excludingChildBadge(textRect, node: node)
                if textRect.width > 1, textRect.height > 1 {
                    context.draw(
                        Text(node.text)
                            .font(FlorettaTitleFont.font(design: node.fontDesign, size: node.fontSize))
                            .foregroundStyle(color(node.textColor)),
                        in: textRect
                    )
                }
                TopicTagCanvas.draw(
                    node: node,
                    in: rect,
                    context: context,
                    color: color,
                    ink: color(node.textColor)
                )
            }
            for line in lines where !line.title.isEmpty {
                let canvasRect = RelationshipLine.labelRect(
                    center: line.labelCenter(straight: false),
                    size: line.labelSize
                )
                let rect = local(canvasRect)
                guard rect.width > 1, rect.height > 1 else { continue }
                let pill = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(pill, with: .color(.white))
                context.stroke(pill, with: .color(color(RelationshipGeometry.ink).opacity(0.45)), lineWidth: 1)
                let textRect = rect.insetBy(dx: 6, dy: 2)
                if textRect.width > 1, textRect.height > 1 {
                    context.draw(
                        Text(line.title)
                            .font(.system(size: RelationshipGeometry.labelFontSize))
                            .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.16)),
                        in: textRect
                    )
                }
            }
            for mark in summaries {
                var brace = Path()
                brace.move(to: local(mark.braceTop))
                brace.addLine(to: local(mark.braceMid))
                brace.addLine(to: local(mark.braceBottom))
                context.stroke(
                    brace,
                    with: .color(color(SummaryGeometry.summaryInk)),
                    style: StrokeStyle(lineWidth: SummaryGeometry.lineWidth, lineCap: .round, lineJoin: .round)
                )
                let rect = local(mark.topicRect)
                guard rect.width > 1, rect.height > 1 else { continue }
                let card = Path(roundedRect: rect, cornerRadius: 8)
                context.fill(card, with: .color(.white))
                context.stroke(card, with: .color(color(SummaryGeometry.summaryInk)), lineWidth: SummaryGeometry.lineWidth)
                let textRect = rect.insetBy(dx: 8, dy: 4)
                if textRect.width > 1, textRect.height > 1, !mark.text.isEmpty {
                    context.draw(
                        Text(mark.text)
                            .font(.system(size: SummaryGeometry.topicFontSize))
                            .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.16)),
                        in: textRect
                    )
                }
            }
            for sticky in stickies {
                let rect = local(CanvasPlacement.stickyCanvasRect(sticky))
                guard rect.width > 1, rect.height > 1 else { continue }
                let path = Path(roundedRect: rect, cornerRadius: 8)
                context.fill(path, with: .color(color(sticky.color.fill)))
                context.stroke(path, with: .color(color(sticky.color.ink).opacity(0.35)), lineWidth: 1)
                let textRect = rect.insetBy(dx: 10, dy: 8)
                if textRect.width > 1, textRect.height > 1, !sticky.text.isEmpty {
                    context.draw(
                        Text(sticky.text)
                            .font(.system(size: 15))
                            .foregroundStyle(color(sticky.color.ink)),
                        in: textRect
                    )
                }
            }
        }
        .frame(width: renderBounds.width, height: renderBounds.height)
        .background(paper)
        .clipped()
    }

    private func excludingChildBadge(_ textRect: CGRect, node: NodeFrame) -> CGRect {
        let badge = node.childBadgeInset
        guard badge > 0, textRect.width > 0 else { return textRect }
        var rect = textRect
        if node.childBadgeOnMinX {
            rect.origin.x += badge
        }
        rect.size.width = max(0, rect.width - badge)
        return rect
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - renderBounds.minX, y: point.y - renderBounds.minY)
    }

    private func stroke(_ line: RelationshipLine, in context: GraphicsContext) {
        var curve = Path()
        curve.move(to: local(line.curve.start))
        curve.addCurve(
            to: local(line.curve.end),
            control1: local(line.curve.control1),
            control2: local(line.curve.control2)
        )
        let ink = color(line.curve.color)
        context.stroke(
            curve,
            with: .color(ink),
            style: StrokeStyle(lineWidth: line.curve.lineWidth, lineCap: .round, dash: [7, 5])
        )
        let head = RelationshipGeometry.arrow(tip: line.curve.end, from: line.curve.control2)
        var arrow = Path()
        arrow.move(to: local(line.curve.end))
        arrow.addLine(to: local(head.left))
        arrow.addLine(to: local(head.right))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(ink))
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(origin: local(rect.origin), size: rect.size)
    }

    private func color(_ value: BranchColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}

struct ExportImageBitmap: @unchecked Sendable {
    var hash: String
    var image: CGImage
}

/// Page-resolution images for PDF/PNG. Spills each asset, asks ImageIO for the
/// longest edge the page needs, and does not write the thumbnail LRU.
enum ImageExportLoader {
    static func spillDirectory(cacheDirectory: URL?) -> URL {
        if let cacheDirectory {
            return cacheDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("spill", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("floretta-export-spill-\(UUID().uuidString)", isDirectory: true)
    }

    static func bitmaps(
        document: MindMapDocument,
        archive: URL?,
        entries: [ZipStoredEntry],
        spillDirectory: URL,
        scale: Double
    ) -> [ExportImageBitmap] {
        images(
            document: document,
            archive: archive,
            entries: entries,
            spillDirectory: spillDirectory,
            scale: scale
        ).map { ExportImageBitmap(hash: $0.key, image: $0.value) }
    }

    static func images(
        document: MindMapDocument,
        archive: URL?,
        entries: [ZipStoredEntry],
        spillDirectory: URL,
        scale: Double
    ) -> [String: CGImage] {
        guard let archive else { return [:] }
        try? FileManager.default.createDirectory(at: spillDirectory, withIntermediateDirectories: true)
        let files = FoundationStreamingFiles()
        var decoded: [String: CGImage] = [:]
        for frame in LayoutEngine().layout(document) {
            let slot = ImageSlot.slot(nodeWidth: Double(frame.size.width))
            for hash in frame.thumbnailHashes where decoded[hash] == nil {
                guard let entry = entries.first(where: { $0.sha256 == hash }) else { continue }
                guard let image = decode(
                    entry: entry,
                    hash: hash,
                    archive: archive,
                    spillDirectory: spillDirectory,
                    slot: slot,
                    scale: scale,
                    files: files
                ) else { continue }
                decoded[hash] = image
            }
        }
        return decoded
    }

    private static func decode(
        entry: ZipStoredEntry,
        hash: String,
        archive: URL,
        spillDirectory: URL,
        slot: ImageSlotRect,
        scale: Double,
        files: FoundationStreamingFiles
    ) -> CGImage? {
        guard let data = try? ThumbnailPipeline.decodeSpilled(
            entry: entry,
            archiveURL: archive,
            spillDirectory: spillDirectory,
            files: files,
            longestEdge: { spill in
                let source = pixelSize(of: spill) ?? ImagePixelSize(width: 0, height: 0)
                return ImageDecodePlanKind.export(
                    hash: hash,
                    source: source,
                    slot: slot,
                    scale: scale
                ).longestEdge
            },
            decoder: ImageIOThumbnailDecoder()
        ) else { return nil }
        return ImageIOThumbnailDecoder.image(from: data)
    }

    private static func pixelSize(of url: URL) -> ImagePixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        guard let width = number(properties[kCGImagePropertyPixelWidth]),
              let height = number(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0 else { return nil }
        return ImagePixelSize(width: width, height: height)
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }
}
