import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum LayoutKind: String, CaseIterable, Codable, Equatable, Sendable {
    /// Root centered, children split left and right. The shipped mind map.
    case bilateral
    /// Root at the left, every branch grows right (XMind 逻辑图).
    case logicChart
    /// Root at the top, every branch grows down (XMind 组织结构图).
    case orgChart
    /// One horizontal spine; first-level topics alternate above and below it (XMind 时间轴).
    case timeline
    /// A horizontal spine with diagonal ribs (XMind 鱼骨图).
    case fishbone
    /// One column per depth, one row band per subtree (XMind 树型表格).
    case treeTable
    /// A two-dimensional grid: column headers, row bands, crossing cells (XMind 矩阵图).
    case matrix

    /// Localization key for a structure picker. The app resolves it; Core stays string-free.
    public var displayNameKey: String {
        switch self {
        case .bilateral: return "layout.bilateral"
        case .logicChart: return "layout.logicChart"
        case .orgChart: return "layout.orgChart"
        case .timeline: return "layout.timeline"
        case .fishbone: return "layout.fishbone"
        case .treeTable: return "layout.treeTable"
        case .matrix: return "layout.matrix"
        }
    }

    /// The one place a structure joins the engine. Adding a kind is one case
    /// above, one `StructureLayout` file, one line below, and one geometry test.
    public func makeLayout(geometry: LayoutGeometry) -> any StructureLayout {
        switch self {
        case .bilateral: return BilateralLayout(geometry: geometry)
        case .logicChart: return LogicChartLayout(geometry: geometry)
        case .orgChart: return OrgChartLayout(geometry: geometry)
        case .timeline: return TimelineLayout(geometry: geometry)
        case .fishbone: return FishboneLayout(geometry: geometry)
        case .treeTable: return TreeTableLayout(geometry: geometry)
        case .matrix: return MatrixLayout(geometry: geometry)
        }
    }
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
    /// Audio waveform hashes, kept separate so audio never reserves an image layout slot.
    public var audioWaveformHashes: [String] = []
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
    public var textAlignment: MindMapTextAlignment = .center
    public var subtitle: String = ""
    public var subtitleFontSize: CGFloat = 0
    public var subtitleHeight: CGFloat = 0

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
        audioWaveformHashes: [String] = [],
        fileBadges: [FileBadge] = [],
        labels: [String] = [],
        markerIDs: [String] = [],
        tagBandHeight: CGFloat = 0,
        childBadgeInset: CGFloat = 0,
        childBadgeOnMinX: Bool = false,
        textAlignment: MindMapTextAlignment = .center,
        subtitle: String = "",
        subtitleFontSize: CGFloat = 0,
        subtitleHeight: CGFloat = 0
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
        self.audioWaveformHashes = audioWaveformHashes
        self.fileBadges = fileBadges
        self.labels = labels
        self.markerIDs = markerIDs
        self.tagBandHeight = tagBandHeight
        self.childBadgeInset = childBadgeInset
        self.childBadgeOnMinX = childBadgeOnMinX
        self.textAlignment = textAlignment
        self.subtitle = subtitle
        self.subtitleFontSize = subtitleFontSize
        self.subtitleHeight = subtitleHeight
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

    /// The chrome percent mirrors the nearest legal interactive zoom stop.
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
    /// Structure to place. `LayoutEngine.forDocument` follows the document.
    public var kind: LayoutKind
    public var cache: TextMeasurementCache
    public var metrics: LayoutMetrics
    public var appearance: LayoutAppearance
    /// Multiplier from the current appearance profile. 1 keeps theme sizes.
    public var fontSizeScale: CGFloat = 1
    /// Painted family id (`eb-garamond`, `system-serif`, …). Empty keeps the
    /// historical Helvetica → system UI measurement path.
    public var fontFamilyID: String = ""

    public init(
        kind: LayoutKind = .bilateral,
        cache: TextMeasurementCache = TextMeasurementCache(),
        metrics: LayoutMetrics = LayoutMetrics(),
        appearance: LayoutAppearance = .standard,
        fontSizeScale: CGFloat = 1,
        fontFamilyID: String = ""
    ) {
        self.kind = kind
        self.cache = cache
        self.metrics = metrics
        self.appearance = appearance
        self.fontSizeScale = fontSizeScale
        self.fontFamilyID = fontFamilyID
    }

    /// Engine that follows the structure stored on the document.
    /// The canvas and the PNG/PDF exporter both build their engine this way, so a
    /// map cannot be drawn as one structure and exported as another.
    public static func forDocument(
        _ document: MindMapDocument,
        cache: TextMeasurementCache = TextMeasurementCache(),
        metrics: LayoutMetrics = LayoutMetrics(),
        appearance: LayoutAppearance = .standard,
        fontSizeScale: CGFloat = 1,
        fontFamilyID: String = ""
    ) -> LayoutEngine {
        LayoutEngine(
            kind: document.layoutKind,
            cache: cache,
            metrics: metrics,
            appearance: appearance,
            fontSizeScale: fontSizeScale,
            fontFamilyID: fontFamilyID
        )
    }

    public func fontSize(depth: Int) -> CGFloat {
        metrics.fontSize(depth: depth) * max(fontSizeScale, 0.01)
    }

    /// `scheme` selects the light or dark set of the document's preset.
    /// An unset theme in light mode keeps `appearance`, so a saved map with no theme id stays on `LayoutAppearance.standard`.
    /// `profile` overlays the user's appearance mode (paper, fill, ink, corner, type scale).
    public func layout(
        _ document: MindMapDocument,
        scheme: MapColorScheme = .light,
        profile: AppearanceProfile? = nil
    ) -> [NodeFrame] {
        var resolved = MapThemeCatalog.appearance(
            themeID: document.themeID,
            scheme: scheme,
            fallback: appearance
        )
        if let profile {
            resolved = profile.applying(to: resolved, scheme: scheme)
        }
        let scale = CGFloat(profile?.clampedFontSizeScale ?? Double(fontSizeScale))
        let familyID = profile?.fontFamilyID ?? fontFamilyID
        let geometry = LayoutGeometry(
            cache: cache,
            metrics: metrics,
            appearance: resolved,
            fontSizeScale: scale,
            fontFamilyID: familyID
        )
        return kind.makeLayout(geometry: geometry).place(document)
    }
}
