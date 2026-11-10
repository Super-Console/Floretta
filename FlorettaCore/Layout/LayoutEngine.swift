import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum LayoutKind: Equatable, Sendable {
    case bilateral
}

public struct BranchColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    /// Named separately from the `blue` component so `.blue` is not the channel.
    public static let white = BranchColor(red: 1, green: 1, blue: 1)
    public static let black = BranchColor(red: 0, green: 0, blue: 0)
    public static let selectionBlue = BranchColor(red: 0.2, green: 0.45, blue: 1)

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public func lightened(by amount: Double) -> BranchColor {
        BranchColor(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount
        )
    }
}

public struct BranchPalette: Equatable, Sendable {
    public var colors: [BranchColor]

    public static let standard = BranchPalette(colors: [
        BranchColor(red: 0.86, green: 0.33, blue: 0.24),
        BranchColor(red: 0.18, green: 0.52, blue: 0.82),
        BranchColor(red: 0.22, green: 0.62, blue: 0.38),
        BranchColor(red: 0.90, green: 0.62, blue: 0.16),
        BranchColor(red: 0.52, green: 0.36, blue: 0.74),
    ])

    public func color(at index: Int) -> BranchColor {
        guard !colors.isEmpty else { return .black }
        let wrapped = index % colors.count
        return colors[wrapped >= 0 ? wrapped : wrapped + colors.count]
    }
}

public struct LayoutMetrics: Equatable, Sendable {
    public var centerFontSize: CGFloat = 30
    public var level1FontSize: CGFloat = 20
    public var level2FontSize: CGFloat = 18
    public var deeperFontSize: CGFloat = 16
    public var maxTextWidth: CGFloat = 240
    public var horizontalGap: CGFloat = 56
    public var siblingGap: CGFloat = 18

    public init() {}

    public func fontSize(depth: Int) -> CGFloat {
        switch depth {
        case 0: return centerFontSize
        case 1: return level1FontSize
        case 2: return level2FontSize
        default: return deeperFontSize
        }
    }

    public func linkWidth(depth: Int) -> CGFloat {
        max(1, 3 - CGFloat(max(depth, 0)) * 0.5)
    }
}

public struct LayoutAppearance: Equatable, Sendable {
    public var centerFill: BranchColor = .white
    public var centerBorder: BranchColor = .black
    public var centerText: BranchColor = .black
    public var level1Text: BranchColor = .white
    public var deeperText: BranchColor = .black
    public var deeperFillMix: Double = 0.82
    public var showsShadows: Bool = false
    public var palette: BranchPalette = .standard
    public var cornerRadius: CGFloat = 8
    /// Nil keeps the depth-based width from `LayoutMetrics.linkWidth`.
    /// A color preset sets one thickness for every link, and for any topic
    /// that does not already store its own `borderWidth`.
    public var linkStroke: CGFloat? = nil
    /// Nil keeps the platform canvas. A theme paper is one color for the whole map.
    public var canvasBackground: BranchColor? = nil
    /// Nil keeps the center fill and the branch fills. Set, every depth uses this fill.
    public var uniformFill: BranchColor? = nil
    /// Nil keeps the center border and the branch borders.
    public var uniformStroke: BranchColor? = nil
    /// Nil keeps the 1.5pt stroke unless the node stores its own width.
    public var uniformStrokeWidth: CGFloat? = nil
    /// Nil keeps the branch color on the curve.
    public var edgeColor: BranchColor? = nil
    /// Nil keeps `LayoutMetrics.linkWidth`. Set, this is the width at the parent end.
    public var edgeStartWidth: CGFloat? = nil
    /// Nil keeps a constant width. A smaller value tapers the same cubic toward the child.
    public var edgeEndWidth: CGFloat? = nil
    /// Used when the node does not store a face. "serif" is the root face. "default" is the system sans.
    public var rootFontDesign: String = "default"
    public var bodyFontDesign: String = "default"
    /// Extra width on the outer side of a non-root node. Zero reserves nothing.
    /// The app has no child-count badge to draw, so this is only the empty slot.
    public var childCountBadgeInset: CGFloat = 0
    /// Orange for that slot. Nil when the theme does not name one.
    public var childCountBadgeColor: BranchColor? = nil

    public static let standard = LayoutAppearance()
}

public struct LinkCurve: Equatable, Sendable {
    public var start: CGPoint
    public var control1: CGPoint
    public var control2: CGPoint
    public var end: CGPoint
    public var lineWidth: CGFloat
    /// Width at `end`. Equal to `lineWidth` for a constant stroke.
    /// A smaller value is the taper of this cubic, stored with the layout, not a second path.
    public var endWidth: CGFloat
    public var color: BranchColor

    public init(
        start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        end: CGPoint,
        lineWidth: CGFloat,
        endWidth: CGFloat? = nil,
        color: BranchColor
    ) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
        self.lineWidth = lineWidth
        self.endWidth = endWidth ?? lineWidth
        self.color = color
    }

    public var isTapered: Bool {
        abs(lineWidth - endWidth) > 0.05
    }

    public func point(at t: CGFloat) -> CGPoint {
        let clamped = min(1, max(0, t))
        let u = 1 - clamped
        let uu = u * u
        let tt = clamped * clamped
        return CGPoint(
            x: uu * u * start.x + 3 * uu * clamped * control1.x + 3 * u * tt * control2.x + tt * clamped * end.x,
            y: uu * u * start.y + 3 * uu * clamped * control1.y + 3 * u * tt * control2.y + tt * clamped * end.y
        )
    }

    /// Outline of this cubic. The four control points stay the layout curve.
    /// Callers fill the outline. They do not build another edge.
    public func taperedOutline(samples: Int = 12) -> [CGPoint] {
        let count = max(samples, 2)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(count)
        right.reserveCapacity(count)
        for index in 0..<count {
            let t = CGFloat(index) / CGFloat(count - 1)
            let current = point(at: t)
            let tangent = derivative(at: t)
            let length = hypot(tangent.x, tangent.y)
            let nx: CGFloat
            let ny: CGFloat
            if length > 0.001 {
                nx = -tangent.y / length
                ny = tangent.x / length
            } else {
                nx = 0
                ny = -1
            }
            let width = lineWidth + (endWidth - lineWidth) * t
            let half = width / 2
            left.append(CGPoint(x: current.x + nx * half, y: current.y + ny * half))
            right.append(CGPoint(x: current.x - nx * half, y: current.y - ny * half))
        }
        return left + right.reversed()
    }

    private func derivative(at t: CGFloat) -> CGPoint {
        let clamped = min(1, max(0, t))
        let u = 1 - clamped
        return CGPoint(
            x: 3 * u * u * (control1.x - start.x)
                + 6 * u * clamped * (control2.x - control1.x)
                + 3 * clamped * clamped * (end.x - control2.x),
            y: 3 * u * u * (control1.y - start.y)
                + 6 * u * clamped * (control2.y - control1.y)
                + 3 * clamped * clamped * (end.y - control2.y)
        )
    }
}

public struct NodeFrame: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var origin: CGPoint
    public var size: CGSize
    public var depth: Int
    public var fontSize: CGFloat
    public var isRoot: Bool
    public var parentID: UUID?
    public var fill: BranchColor
    public var border: BranchColor
    public var textColor: BranchColor
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat = 1.5
    public var hidesFill: Bool = false
    public var bold: Bool = false
    public var italic: Bool = false
    public var strikethrough: Bool = false
    public var underline: Bool = false
    public var fontDesign: String = "default"
    public var link: LinkCurve?
    /// True when the frame is a free node. It has no parent and no hierarchy curve.
    public var isFree: Bool = false
    /// Attachment sizes, one `filename size` line each. The canvas draws non-image lines as `fileBadges`.
    public var caption: String = ""
    /// Image attachment hashes that may have a thumbnail. Used for viewport unload.
    public var thumbnailHashes: [String] = []
    /// Non-image attachments. Each row is a type icon, the filename, and the size.
    public var fileBadges: [FileBadge] = []
    /// User-written topic labels. Drawn under the title. Empty when the topic has none.
    public var labels: [String] = []
    /// Marker ids from the topic, in file order.
    public var markerIDs: [String] = []
    /// Extra height already included in `size` for labels and markers. Zero when there are none.
    public var tagBandHeight: CGFloat = 0
    /// Outer slot already included in `size`. Zero when the theme reserves none.
    public var childBadgeInset: CGFloat = 0
    /// True when that slot sits on `minX`. False puts it on `maxX`.
    public var childBadgeOnMinX: Bool = false

    public init(
        id: UUID,
        text: String,
        origin: CGPoint,
        size: CGSize,
        depth: Int,
        fontSize: CGFloat,
        isRoot: Bool,
        parentID: UUID? = nil,
        fill: BranchColor,
        border: BranchColor,
        textColor: BranchColor,
        cornerRadius: CGFloat,
        borderWidth: CGFloat = 1.5,
        hidesFill: Bool = false,
        bold: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false,
        underline: Bool = false,
        fontDesign: String = "default",
        link: LinkCurve? = nil,
        caption: String = "",
        isFree: Bool = false,
        thumbnailHashes: [String] = [],
        fileBadges: [FileBadge] = [],
        labels: [String] = [],
        markerIDs: [String] = [],
        tagBandHeight: CGFloat = 0,
        childBadgeInset: CGFloat = 0,
        childBadgeOnMinX: Bool = false
    ) {
        self.id = id
        self.text = text
        self.origin = origin
        self.size = size
        self.depth = depth
        self.fontSize = fontSize
        self.isRoot = isRoot
        self.parentID = parentID
        self.fill = fill
        self.border = border
        self.textColor = textColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.hidesFill = hidesFill
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
        self.fontDesign = fontDesign
        self.link = link
        self.isFree = isFree
        self.caption = caption
        self.thumbnailHashes = thumbnailHashes
        self.fileBadges = fileBadges
        self.labels = labels
        self.markerIDs = markerIDs
        self.tagBandHeight = tagBandHeight
        self.childBadgeInset = childBadgeInset
        self.childBadgeOnMinX = childBadgeOnMinX
    }

    public var rect: CGRect { CGRect(origin: origin, size: size) }
    public var frame: CGRect { rect }
}

public enum CanvasDirection: String, Equatable, Sendable, CaseIterable {
    case up, down, left, right
}

public struct CanvasInteraction: Equatable, Sendable {
    public var hoveredNodeID: UUID?
    public var selectedNodeID: UUID?
    public var selectionBorder: BranchColor
    public var selectionBorderWidth: CGFloat
    public var resizeHandles: [CanvasDirection]
    public var showsShadows: Bool

    public static let standard = CanvasInteraction(
        hoveredNodeID: nil,
        selectedNodeID: nil,
        selectionBorder: .selectionBlue,
        selectionBorderWidth: 1.5,
        resizeHandles: CanvasDirection.allCases,
        showsShadows: false
    )

    public var addDirections: [CanvasDirection] {
        hoveredNodeID == nil ? [] : CanvasDirection.allCases
    }

    public var showsSelectionChrome: Bool { selectedNodeID != nil }
}

public struct CanvasSheet: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

public struct CanvasChrome: Equatable, Sendable {
    public var isInfinite: Bool
    public var zoomPercent: Int
    public var zoomIsClickable: Bool
    public var fitControlVisible: Bool
    public var sheets: [CanvasSheet]
    public var activeSheetIndex: Int

    public static let standard = CanvasChrome(
        isInfinite: true,
        zoomPercent: 100,
        zoomIsClickable: true,
        fitControlVisible: true,
        sheets: [CanvasSheet(title: "Canvas")],
        activeSheetIndex: 0
    )

    public mutating func addSheet(title: String) {
        sheets.append(CanvasSheet(title: title))
    }

    public mutating func selectSheet(_ index: Int) {
        guard sheets.indices.contains(index) else { return }
        activeSheetIndex = index
    }

    /// The chrome percent is always a legal stop, never a raw value such as 137.
    public mutating func syncZoomPercent(toScale scale: CGFloat) {
        zoomPercent = ZoomStop.displayPercent(forScale: scale)
    }
}

public enum CanvasCommand: Equatable, Sendable {
    case hover(UUID?)
    case select(UUID?)
    case addChild(parentID: UUID, direction: CanvasDirection)
    case addFloatingTopic(at: CGPoint)
}

public enum CanvasCommands {
    @discardableResult
    public static func apply(
        _ command: CanvasCommand,
        document: inout MindMapDocument,
        interaction: inout CanvasInteraction
    ) -> UUID? {
        switch command {
        case .hover(let id):
            interaction.hoveredNodeID = id
            return nil
        case .select(let id):
            interaction.selectedNodeID = id
            return nil
        case .addChild(let parentID, _):
            let child = MindMapNode(text: "新主题")
            guard insert(child, under: parentID, nodes: &document.roots) else { return nil }
            return child.id
        case .addFloatingTopic(let point):
            let node = MindMapNode(
                text: "浮动主题",
                position: MindMapPoint(x: Double(point.x), y: Double(point.y))
            )
            document.roots.append(node)
            return node.id
        }
    }

    private static func insert(_ child: MindMapNode, under parentID: UUID, nodes: inout [MindMapNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == parentID {
                nodes[index].children.append(child)
                return true
            }
            if insert(child, under: parentID, nodes: &nodes[index].children) {
                return true
            }
        }
        return false
    }
}

public struct LayoutEngine: Sendable {
    public var kind: LayoutKind
    public var cache: TextMeasurementCache
    public var metrics: LayoutMetrics
    public var appearance: LayoutAppearance

    public init(
        kind: LayoutKind = .bilateral,
        cache: TextMeasurementCache = TextMeasurementCache(),
        metrics: LayoutMetrics = LayoutMetrics(),
        appearance: LayoutAppearance = .standard
    ) {
        self.kind = kind
        self.cache = cache
        self.metrics = metrics
        self.appearance = appearance
    }

    public func fontSize(depth: Int) -> CGFloat {
        metrics.fontSize(depth: depth)
    }

    /// `scheme` selects the light or dark set of the document's preset.
    /// An unset theme in light mode keeps `appearance`, so a saved map with no theme id stays on `LayoutAppearance.standard`.
    public func layout(_ document: MindMapDocument, scheme: MapColorScheme = .light) -> [NodeFrame] {
        let resolved = MapThemeCatalog.appearance(
            themeID: document.themeID,
            scheme: scheme,
            fallback: appearance
        )
        if resolved == appearance {
            return placed(document)
        }
        var themed = self
        themed.appearance = resolved
        return themed.placed(document)
    }

    private func placed(_ document: MindMapDocument) -> [NodeFrame] {
        switch kind {
        case .bilateral:
            return bilateral(document)
        }
    }

    private struct Measured {
        var node: MindMapNode
        var size: CGSize
        var children: [Measured]
        var blockHeight: CGFloat
        var depth: Int
        var branch: BranchColor
    }

    private enum Side {
        case left
        case right
    }

    private func bilateral(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        for root in document.roots {
            collectHeights(root, depth: 0, into: &levelHeights)
        }
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        var placedAutoRoot = false
        for root in document.roots {
            if root.position != nil {
                appendManual(root, depth: 0, parentID: nil, isRoot: true, parentRect: nil, branch: .black, heights: levelHeights, into: &frames)
                continue
            }
            let autos = root.isCollapsed ? [] : root.children.filter { $0.position == nil }
            let sides = split(autos, parent: root, depth: 1, heights: levelHeights)
            let rootSize = nodeSize(root, depth: 0, heights: levelHeights)
            let blockHeight = max(rootSize.height, stackHeight(sides.right), stackHeight(sides.left))
            let centerY = placedAutoRoot ? nextTop + blockHeight / 2 : 0
            let origin = CGPoint(x: -rootSize.width / 2, y: centerY - rootSize.height / 2)
            let rootFrame = makeFrame(
                node: root,
                origin: origin,
                size: rootSize,
                depth: 0,
                isRoot: true,
                parentID: nil,
                branch: .black,
                link: nil
            )
            frames.append(rootFrame)
            place(sides.right, side: .right, parent: rootFrame, centerY: centerY, heights: levelHeights, into: &frames)
            place(sides.left, side: .left, parent: rootFrame, centerY: centerY, heights: levelHeights, into: &frames)
            if !root.isCollapsed {
                for child in root.children where child.position != nil {
                    let color = appearance.palette.color(at: childIndex(of: child, in: root))
                    appendManual(child, depth: 1, parentID: root.id, isRoot: false, parentRect: rootFrame.rect, branch: color, heights: levelHeights, into: &frames)
                }
            }
            nextTop = centerY + blockHeight / 2 + metrics.siblingGap * 2
            placedAutoRoot = true
        }
        // Free nodes are not measured into `levelHeights` and are not passed to `split`.
        // Their origin is the stored point, including while that point is being dragged.
        for node in document.freeNodes {
            appendFree(node, into: &frames)
        }
        return frames
    }

    private func appendFree(_ node: MindMapNode, into frames: inout [NodeFrame]) {
        let font = resolvedFontSize(node, depth: 1)
        let raw = cache.size(text: layoutText(node), fontSize: font, maxWidth: metrics.maxTextWidth)
        let size = nodeSize(node, depth: 1, heights: [1: raw.height], reservesChildBadge: false)
        let origin = CGPoint(x: node.position?.x ?? 0, y: node.position?.y ?? 0)
        frames.append(
            makeFrame(
                node: node,
                origin: origin,
                size: size,
                depth: 1,
                isRoot: false,
                parentID: nil,
                branch: appearance.palette.color(at: 0),
                link: nil,
                isFree: true
            )
        )
    }

    private func layoutText(_ node: MindMapNode) -> String {
        NodeAttachmentDrawing.measuredText(node)
    }

    private func collectHeights(_ node: MindMapNode, depth: Int, into heights: inout [Int: CGFloat]) {
        let raw = cache.size(text: layoutText(node), fontSize: resolvedFontSize(node, depth: depth), maxWidth: metrics.maxTextWidth)
        heights[depth] = max(heights[depth] ?? 0, raw.height)
        if node.position != nil || node.isCollapsed { return }
        for child in node.children {
            collectHeights(child, depth: depth + 1, into: &heights)
        }
    }

    private func nodeSize(
        _ node: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat],
        reservesChildBadge: Bool = false
    ) -> CGSize {
        let font = resolvedFontSize(node, depth: depth)
        let raw = cache.size(text: layoutText(node), fontSize: font, maxWidth: metrics.maxTextWidth)
        let band = thumbnailBand(node)
        let files = FileBadgeLayout.fileAttachments(in: node)
        let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: files.count))
        let tagBand = CGFloat(TopicTagLayout.bandHeight(labelCount: node.labels.count, markerCount: node.markers.count))
        let imageWidth = band > 0 ? CGFloat(ImageSlot.maxWidth + ImageSlot.horizontalInset * 2) : 0
        var fileWidth: CGFloat = 0
        if !files.isEmpty {
            let label = files.map { "\($0.filename) \(AttachmentByteFormat.label($0.byteCount))" }.joined(separator: "\n")
            let measured = cache.size(text: label, fontSize: font, maxWidth: metrics.maxTextWidth)
            fileWidth = measured.width + CGFloat(FileBadgeMetrics.iconSide + FileBadgeMetrics.gap + FileBadgeMetrics.horizontalInset * 2)
        }
        let width = max(raw.width, CGFloat(node.style?.topicWidth ?? 0), imageWidth, fileWidth)
        let badge: CGFloat = reservesChildBadge ? appearance.childCountBadgeInset : 0
        return CGSize(width: width + badge, height: (heights[depth] ?? raw.height) + band + fileBand + tagBand)
    }

    private func thumbnailBand(_ node: MindMapNode) -> CGFloat {
        let hasImage = node.attachments.contains { AttachmentKind.isImageExtension($0.fileExtension) }
        return CGFloat(ImageSlot.bandHeight(hasImage: hasImage))
    }

    private func resolvedFontSize(_ node: MindMapNode, depth: Int) -> CGFloat {
        if let size = node.style?.fontSize, size > 0 { return CGFloat(size) }
        return fontSize(depth: depth)
    }

    private func split(
        _ children: [MindMapNode],
        parent: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat]
    ) -> (left: [Measured], right: [Measured]) {
        var left: [Measured] = []
        var right: [Measured] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        for child in children {
            let color = appearance.palette.color(at: childIndex(of: child, in: parent))
            let block = measure(child, depth: depth, branch: color, heights: heights)
            let rightNext = right.isEmpty ? block.blockHeight : rightHeight + metrics.siblingGap + block.blockHeight
            let leftNext = left.isEmpty ? block.blockHeight : leftHeight + metrics.siblingGap + block.blockHeight
            if rightNext < leftNext || (rightNext == leftNext && right.count <= left.count) {
                right.append(block)
                rightHeight = rightNext
            } else {
                left.append(block)
                leftHeight = leftNext
            }
        }
        return (left, right)
    }

    private func measure(
        _ node: MindMapNode,
        depth: Int,
        branch: BranchColor,
        heights: [Int: CGFloat]
    ) -> Measured {
        let size = nodeSize(
            node,
            depth: depth,
            heights: heights,
            reservesChildBadge: depth > 0 && appearance.childCountBadgeInset > 0
        )
        let kids = node.isCollapsed ? [] : node.children.filter { $0.position == nil }
        let children = kids.map { measure($0, depth: depth + 1, branch: branch, heights: heights) }
        return Measured(
            node: node,
            size: size,
            children: children,
            blockHeight: stacked(children, minimum: size.height),
            depth: depth,
            branch: branch
        )
    }

    private func stackHeight(_ blocks: [Measured]) -> CGFloat {
        stacked(blocks, minimum: 0)
    }

    private func stacked(_ blocks: [Measured], minimum: CGFloat) -> CGFloat {
        guard !blocks.isEmpty else { return minimum }
        let gaps = metrics.siblingGap * CGFloat(blocks.count - 1)
        return max(minimum, blocks.reduce(CGFloat(0)) { $0 + $1.blockHeight } + gaps)
    }

    private func place(
        _ blocks: [Measured],
        side: Side,
        parent: NodeFrame,
        centerY: CGFloat,
        heights: [Int: CGFloat],
        into frames: inout [NodeFrame]
    ) {
        let height = stackHeight(blocks)
        var top = centerY - height / 2
        for block in blocks {
            let y = top + (block.blockHeight - block.size.height) / 2
            let x = side == .right
                ? parent.rect.maxX + metrics.horizontalGap
                : parent.rect.minX - metrics.horizontalGap - block.size.width
            let origin = CGPoint(x: x, y: y)
            let rect = CGRect(origin: origin, size: block.size)
            let frame = makeFrame(
                node: block.node,
                origin: origin,
                size: block.size,
                depth: block.depth,
                isRoot: false,
                parentID: parent.id,
                branch: block.branch,
                link: curve(from: parent.rect, to: rect, side: side, depth: block.depth, color: block.branch),
                childBadgeInset: appearance.childCountBadgeInset,
                childBadgeOnMinX: side == .left
            )
            frames.append(frame)
            place(block.children, side: side, parent: frame, centerY: rect.midY, heights: heights, into: &frames)
            if !block.node.isCollapsed {
                for child in block.node.children where child.position != nil {
                    appendManual(
                        child,
                        depth: block.depth + 1,
                        parentID: block.node.id,
                        isRoot: false,
                        parentRect: rect,
                        branch: block.branch,
                        heights: heights,
                        into: &frames
                    )
                }
            }
            top += block.blockHeight + metrics.siblingGap
        }
    }

    private func appendManual(
        _ node: MindMapNode,
        depth: Int,
        parentID: UUID?,
        isRoot: Bool,
        parentRect: CGRect?,
        branch: BranchColor,
        heights: [Int: CGFloat],
        into frames: inout [NodeFrame]
    ) {
        guard let position = node.position else { return }
        let reserveBadge = !isRoot && appearance.childCountBadgeInset > 0
        let size = nodeSize(node, depth: depth, heights: heights, reservesChildBadge: reserveBadge)
        let origin = CGPoint(x: position.x, y: position.y)
        let rect = CGRect(origin: origin, size: size)
        let side: Side = rect.midX >= (parentRect?.midX ?? rect.midX) ? .right : .left
        let link = parentRect.map {
            curve(from: $0, to: rect, side: side, depth: depth, color: branch)
        }
        frames.append(
            makeFrame(
                node: node,
                origin: origin,
                size: size,
                depth: depth,
                isRoot: isRoot,
                parentID: parentID,
                branch: branch,
                link: link,
                childBadgeInset: reserveBadge ? appearance.childCountBadgeInset : 0,
                childBadgeOnMinX: side == .left
            )
        )
    }

    private func makeFrame(
        node: MindMapNode,
        origin: CGPoint,
        size: CGSize,
        depth: Int,
        isRoot: Bool,
        parentID: UUID?,
        branch: BranchColor,
        link: LinkCurve?,
        isFree: Bool = false,
        childBadgeInset: CGFloat = 0,
        childBadgeOnMinX: Bool = false
    ) -> NodeFrame {
        let palette = colors(depth: depth, branch: branch)
        let stored = node.style
        let fill = stored?.fillHex.flatMap(BranchColor.init(hex:)) ?? palette.fill
        let border = stored?.borderHex.flatMap(BranchColor.init(hex:)) ?? palette.border
        let text = stored?.textHex.flatMap(BranchColor.init(hex:)) ?? palette.text
        return NodeFrame(
            id: node.id,
            text: node.text,
            origin: origin,
            size: size,
            depth: depth,
            fontSize: resolvedFontSize(node, depth: depth),
            isRoot: isRoot,
            parentID: parentID,
            fill: fill,
            border: border,
            textColor: text,
            cornerRadius: CGFloat(stored?.cornerRadius ?? Double(appearance.cornerRadius)),
            borderWidth: CGFloat(stored?.borderWidth ?? Double(appearance.uniformStrokeWidth ?? appearance.linkStroke ?? 1.5)),
            hidesFill: stored?.fillStyle == "none",
            bold: stored?.bold ?? false,
            italic: stored?.italic ?? false,
            strikethrough: stored?.strikethrough ?? false,
            underline: stored?.underline ?? false,
            fontDesign: stored?.fontDesign ?? (isRoot ? appearance.rootFontDesign : appearance.bodyFontDesign),
            link: link,
            caption: node.attachmentSizeLabel ?? "",
            isFree: isFree,
            thumbnailHashes: node.attachments.compactMap { attachment in
                AttachmentKind.isImageExtension(attachment.fileExtension)
                    || NodeMediaKind.classify(filename: attachment.filename) == .video
                    ? attachment.sha256 : nil
            },
            fileBadges: FileBadgeLayout.badges(
                attachments: node.attachments,
                nodeWidth: Double(size.width),
                nodeHeight: Double(size.height)
            ),
            labels: node.labels,
            markerIDs: node.markers.map(\.markerId),
            tagBandHeight: CGFloat(TopicTagLayout.bandHeight(
                labelCount: node.labels.count,
                markerCount: node.markers.count
            )),
            childBadgeInset: childBadgeInset,
            childBadgeOnMinX: childBadgeOnMinX
        )
    }

    private func colors(depth: Int, branch: BranchColor) -> (fill: BranchColor, border: BranchColor, text: BranchColor) {
        let text: BranchColor
        if depth == 0 {
            text = appearance.centerText
        } else if depth == 1 {
            text = appearance.level1Text
        } else {
            text = appearance.deeperText
        }
        if appearance.uniformFill == nil, appearance.uniformStroke == nil {
            if depth == 0 {
                return (appearance.centerFill, appearance.centerBorder, text)
            }
            if depth == 1 {
                return (branch, branch, text)
            }
            return (branch.lightened(by: appearance.deeperFillMix), branch, text)
        }
        let fill: BranchColor
        if let uniform = appearance.uniformFill {
            fill = uniform
        } else if depth == 0 {
            fill = appearance.centerFill
        } else if depth == 1 {
            fill = branch
        } else {
            fill = branch.lightened(by: appearance.deeperFillMix)
        }
        let border: BranchColor
        if let uniform = appearance.uniformStroke {
            border = uniform
        } else if depth == 0 {
            border = appearance.centerBorder
        } else {
            border = branch
        }
        return (fill, border, text)
    }

    private func curve(
        from parent: CGRect,
        to child: CGRect,
        side: Side,
        depth: Int,
        color: BranchColor
    ) -> LinkCurve {
        let start: CGPoint
        let end: CGPoint
        if side == .right {
            start = CGPoint(x: parent.maxX, y: parent.midY)
            end = CGPoint(x: child.minX, y: child.midY)
        } else {
            start = CGPoint(x: parent.minX, y: parent.midY)
            end = CGPoint(x: child.maxX, y: child.midY)
        }
        let dx = end.x - start.x
        let startWidth = appearance.edgeStartWidth ?? appearance.linkStroke ?? metrics.linkWidth(depth: depth)
        let endWidth = appearance.edgeEndWidth ?? startWidth
        return LinkCurve(
            start: start,
            control1: CGPoint(x: start.x + dx * 0.5, y: start.y),
            control2: CGPoint(x: end.x - dx * 0.5, y: end.y),
            end: end,
            lineWidth: startWidth,
            endWidth: endWidth,
            color: appearance.edgeColor ?? color
        )
    }

    private func childIndex(of child: MindMapNode, in parent: MindMapNode) -> Int {
        parent.children.firstIndex(where: { $0.id == child.id }) ?? 0
    }
}
