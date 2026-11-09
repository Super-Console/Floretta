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
/// The picture is the nodes and links only: no toolbar, sidebar, grid, or selection.
@MainActor
enum MapExporter {
    static let clippingNotice = "导出已按最大尺寸裁切，超出的内容没有画进文件。"
    static let emptyNotice = "没有可导出的节点。"

    static func visibleFrames(in document: MindMapDocument) -> [NodeFrame] {
        CanvasPlacement.nodes(in: document)
    }

    static func png(document: MindMapDocument, options: MapExportOptions = MapExportOptions()) -> MapExportResult {
        let plan = plan(document: document, options: options)
        guard plan.pointSize.width > 1, plan.pointSize.height > 1 else {
            return empty(plan)
        }
        let renderer = makeRenderer(plan: plan, options: options, document: document)
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

    static func pdf(document: MindMapDocument, options: MapExportOptions = MapExportOptions()) -> MapExportResult {
        let plan = plan(document: document, options: options)
        guard plan.pointSize.width > 1, plan.pointSize.height > 1 else {
            return empty(plan)
        }
        let renderer = makeRenderer(plan: plan, options: options, document: document)
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
        var truncated: Bool
        var notice: String?
        var visibleNodeIDs: [UUID]
    }

    private static func plan(document: MindMapDocument, options: MapExportOptions) -> Plan {
        let frames = visibleFrames(in: document)
        let ids = frames.map(\.id)
        guard let content = CanvasPlacement.contentBounds(in: document),
              content.width > 0, content.height > 0 else {
            return Plan(renderBounds: .zero, pointSize: .zero, truncated: false, notice: emptyNotice, visibleNodeIDs: ids)
        }
        let pad = max(options.padding, 0)
        let padded = content.insetBy(dx: -pad, dy: -pad)
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
            truncated: truncated,
            notice: truncated ? clippingNotice : nil,
            visibleNodeIDs: ids
        )
    }

    private static func makeRenderer(
        plan: Plan,
        options: MapExportOptions,
        document: MindMapDocument
    ) -> ImageRenderer<MapExportView> {
        let view = MapExportView(
            frames: visibleFrames(in: document),
            renderBounds: plan.renderBounds,
            background: options.background
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = options.scale.rawValue
        renderer.isOpaque = options.background == .white
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

/// Nodes and links in export coordinates. No chrome.
private struct MapExportView: View {
    var frames: [NodeFrame]
    var renderBounds: CGRect
    var background: MapExportBackground

    var body: some View {
        Canvas { context, _ in
            for node in frames {
                guard let link = node.link else { continue }
                var curve = Path()
                curve.move(to: local(link.start))
                curve.addCurve(
                    to: local(link.end),
                    control1: local(link.control1),
                    control2: local(link.control2)
                )
                context.stroke(curve, with: .color(color(link.color)), lineWidth: link.lineWidth)
            }
            for node in frames {
                let rect = local(node.frame)
                let path = Path(roundedRect: rect, cornerRadius: node.cornerRadius)
                context.fill(path, with: .color(color(node.fill)))
                context.stroke(path, with: .color(color(node.border)), lineWidth: 1.5)
                context.draw(
                    Text(node.text)
                        .font(.system(size: node.fontSize))
                        .foregroundStyle(color(node.textColor)),
                    in: rect.insetBy(dx: 8, dy: 4)
                )
            }
        }
        .frame(width: renderBounds.width, height: renderBounds.height)
        .background(background == .white ? Color.white : Color.clear)
        .clipped()
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - renderBounds.minX, y: point.y - renderBounds.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(origin: local(rect.origin), size: rect.size)
    }

    private func color(_ value: BranchColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}
