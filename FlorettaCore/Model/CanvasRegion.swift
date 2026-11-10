import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A canvas zone. It is not a topic: it has no parent, no children, and it is
/// not stored in `roots` or `freeNodes`. Nodes that sit inside it keep their
/// existing parents.
public enum CanvasRegionShape: String, Codable, Equatable, Sendable {
    case rectangle
    case ellipse
}

public enum CanvasRegionAxis: Equatable, Sendable {
    case width
    case height
}

/// Size caps. A region can enclose a branch, and it stays finite so a typed
/// value cannot stretch the canvas without a bound.
public enum CanvasRegionLimits {
    public static let minWidth = 48.0
    public static let minHeight = 48.0
    public static let maxWidth = 6400.0
    public static let maxHeight = 6400.0
    public static let defaultWidth = 320.0
    public static let defaultHeight = 200.0
    public static let minStroke = 0.0
    public static let maxStroke = 32.0
    public static let defaultStroke = 2.0
    /// Bottom-right square, in canvas points, that resizes instead of moving.
    public static let resizeHandle = 18.0
    /// Extra canvas points around the enclosed nodes when the user fits the region.
    public static let fitPadding = 24.0
    /// A node flush with the border still counts as enclosed.
    public static let enclosureEpsilon = 0.5

    public static let defaultFill = BranchColor(red: 214.0 / 255.0, green: 228.0 / 255.0, blue: 245.0 / 255.0)
    public static let defaultBorder = BranchColor(red: 74.0 / 255.0, green: 111.0 / 255.0, blue: 165.0 / 255.0)

    public static func clampWidth(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(max(width, minWidth), maxWidth)
    }

    public static func clampHeight(_ height: Double) -> Double {
        guard height.isFinite else { return defaultHeight }
        return min(max(height, minHeight), maxHeight)
    }

    public static func clampStroke(_ width: Double) -> Double {
        guard width.isFinite else { return defaultStroke }
        return min(max(width, minStroke), maxStroke)
    }
}

extension BranchColor {
    /// `#RRGGBB`. Channels outside 0...1 are clamped. Non-finite channels become 0.
    public var hexRGB: String {
        func byte(_ channel: Double) -> Int {
            let unit = channel.isFinite ? min(max(channel, 0), 1) : 0
            return Int((unit * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

/// One rectangular (or 1:1 elliptical) zone on the canvas.
public struct CanvasRegion: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var origin: MindMapPoint
    public var width: Double {
        didSet {
            let clamped = CanvasRegionLimits.clampWidth(width)
            if clamped != width { width = clamped }
        }
    }
    public var height: Double {
        didSet {
            let clamped = CanvasRegionLimits.clampHeight(height)
            if clamped != height { height = clamped }
        }
    }
    public var aspectLocked: Bool
    public var shape: CanvasRegionShape
    public var fill: BranchColor
    public var border: BranchColor
    public var strokeWidth: Double {
        didSet {
            let clamped = CanvasRegionLimits.clampStroke(strokeWidth)
            if clamped != strokeWidth { strokeWidth = clamped }
        }
    }

    public init(
        id: UUID = UUID(),
        label: String = "专区",
        origin: MindMapPoint,
        width: Double = CanvasRegionLimits.defaultWidth,
        height: Double = CanvasRegionLimits.defaultHeight,
        aspectLocked: Bool = false,
        shape: CanvasRegionShape = .rectangle,
        fill: BranchColor = CanvasRegionLimits.defaultFill,
        border: BranchColor = CanvasRegionLimits.defaultBorder,
        strokeWidth: Double = CanvasRegionLimits.defaultStroke
    ) {
        self.id = id
        self.label = label
        if origin.x.isFinite, origin.y.isFinite {
            self.origin = origin
        } else {
            self.origin = MindMapPoint(
                x: origin.x.isFinite ? origin.x : 0,
                y: origin.y.isFinite ? origin.y : 0
            )
        }
        self.width = CanvasRegionLimits.clampWidth(width)
        self.height = CanvasRegionLimits.clampHeight(height)
        self.aspectLocked = aspectLocked
        self.shape = shape
        self.fill = fill
        self.border = border
        self.strokeWidth = CanvasRegionLimits.clampStroke(strokeWidth)
    }

    public var bounds: CGRect {
        CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    /// Height divided by width. Zero when the width is not usable.
    public var aspectRatio: Double {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        return height / width
    }

    public func contains(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite, width > 0, height > 0 else { return false }
        switch shape {
        case .rectangle:
            return x >= origin.x && y >= origin.y && x <= origin.x + width && y <= origin.y + height
        case .ellipse:
            let nx = (x - (origin.x + width / 2)) / (width / 2)
            let ny = (y - (origin.y + height / 2)) / (height / 2)
            return nx * nx + ny * ny <= 1
        }
    }

    public func hitsResizeHandle(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        let handle = CanvasRegionLimits.resizeHandle
        return x >= origin.x + width - handle && x <= origin.x + width
            && y >= origin.y + height - handle && y <= origin.y + height
    }
}

extension CanvasRegion: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case origin
        case width
        case height
        case aspectLocked
        case shape
        case fill
        case border
        case strokeWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        let origin = try container.decode(MindMapPoint.self, forKey: .origin)
        guard origin.x.isFinite, origin.y.isFinite else {
            throw FlorettaCodecError.corrupt("Region \(id.uuidString) has a non-finite origin.")
        }
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        let aspectLocked = try container.decodeIfPresent(Bool.self, forKey: .aspectLocked) ?? false
        let shape = try Self.decodeShape(in: container, id: id)
        let fill = try Self.decodeColor(in: container, key: .fill, id: id, fallback: CanvasRegionLimits.defaultFill)
        let border = try Self.decodeColor(in: container, key: .border, id: id, fallback: CanvasRegionLimits.defaultBorder)
        let strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? CanvasRegionLimits.defaultStroke
        self.init(
            id: id,
            label: label,
            origin: origin,
            width: width,
            height: height,
            aspectLocked: aspectLocked,
            shape: shape,
            fill: fill,
            border: border,
            strokeWidth: strokeWidth
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(origin, forKey: .origin)
        try container.encode(CanvasRegionLimits.clampWidth(width), forKey: .width)
        try container.encode(CanvasRegionLimits.clampHeight(height), forKey: .height)
        try container.encode(aspectLocked, forKey: .aspectLocked)
        try container.encode(shape, forKey: .shape)
        try container.encode(fill.hexRGB, forKey: .fill)
        try container.encode(border.hexRGB, forKey: .border)
        try container.encode(CanvasRegionLimits.clampStroke(strokeWidth), forKey: .strokeWidth)
    }

    private static func decodeShape(
        in container: KeyedDecodingContainer<CodingKeys>,
        id: UUID
    ) throws -> CanvasRegionShape {
        guard let raw = try container.decodeIfPresent(String.self, forKey: .shape) else {
            return .rectangle
        }
        guard let shape = CanvasRegionShape(rawValue: raw) else {
            throw FlorettaCodecError.corrupt(
                "Unknown region shape \"\(raw)\". Regions use rectangle or ellipse."
            )
        }
        return shape
    }

    private static func decodeColor(
        in container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        id: UUID,
        fallback: BranchColor
    ) throws -> BranchColor {
        guard let hex = try container.decodeIfPresent(String.self, forKey: key) else {
            return fallback
        }
        guard let color = BranchColor(hex: hex) else {
            throw FlorettaCodecError.corrupt(
                "Region \(id.uuidString) has a \(key.stringValue) that is not #RRGGBB."
            )
        }
        return color
    }
}

/// Where a region should sit after a resize, a circle conversion, or a fit.
public struct CanvasRegionPlacement: Equatable, Sendable {
    public var origin: MindMapPoint
    public var width: Double
    public var height: Double

    public init(origin: MindMapPoint, width: Double, height: Double) {
        self.origin = origin
        self.width = width
        self.height = height
    }
}

/// Which part of a region the pointer is on. Later regions are painted above earlier ones.
public enum CanvasRegionHit: Equatable, Sendable {
    case body(UUID)
    case resize(UUID)
}

/// Size, hit testing, and fit. None of these functions read or write the topic tree.
public enum CanvasRegionGeometry {
    public static func hit(x: Double, y: Double, in regions: [CanvasRegion]) -> CanvasRegionHit? {
        for region in regions.reversed() {
            if region.hitsResizeHandle(x: x, y: y) { return .resize(region.id) }
            if region.contains(x: x, y: y) { return .body(region.id) }
        }
        return nil
    }

    /// Applies a typed width or height. A locked region keeps `height / width`.
    public static func typed(
        width: Double,
        height: Double,
        axis: CanvasRegionAxis,
        value: Double,
        locked: Bool
    ) -> CanvasRegionPlacement {
        let ratio = height > 0 && width > 0 ? height / width : 0
        switch axis {
        case .width:
            if locked, ratio > 0 {
                let pair = clampPair(value, value * ratio, locked: true, ratio: ratio)
                return CanvasRegionPlacement(origin: MindMapPoint(x: 0, y: 0), width: pair.width, height: pair.height)
            }
            return CanvasRegionPlacement(
                origin: MindMapPoint(x: 0, y: 0),
                width: CanvasRegionLimits.clampWidth(value),
                height: CanvasRegionLimits.clampHeight(height)
            )
        case .height:
            if locked, ratio > 0 {
                let pair = clampPair(value / ratio, value, locked: true, ratio: ratio)
                return CanvasRegionPlacement(origin: MindMapPoint(x: 0, y: 0), width: pair.width, height: pair.height)
            }
            return CanvasRegionPlacement(
                origin: MindMapPoint(x: 0, y: 0),
                width: CanvasRegionLimits.clampWidth(width),
                height: CanvasRegionLimits.clampHeight(value)
            )
        }
    }

    /// Drag delta from the bottom-right handle. The top-left corner stays put.
    /// A locked region follows the axis that moved farther, relative to its start size.
    public static func resized(
        width: Double,
        height: Double,
        dx: Double,
        dy: Double,
        locked: Bool
    ) -> (width: Double, height: Double) {
        let startW = width
        let startH = height
        if !locked || startW <= 0 || startH <= 0 || !dx.isFinite || !dy.isFinite {
            return clampPair(startW + dx, startH + dy, locked: false, ratio: nil)
        }
        let ratio = startH / startW
        let widthDelta = abs(dx) / startW
        let heightDelta = abs(dy) / startH
        if widthDelta >= heightDelta {
            let nextW = startW + dx
            return clampPair(nextW, nextW * ratio, locked: true, ratio: ratio)
        }
        let nextH = startH + dy
        return clampPair(nextH / ratio, nextH, locked: true, ratio: ratio)
    }

    /// Equal width and height, centered on the previous box, drawn as an ellipse.
    public static func circle(_ region: CanvasRegion) -> CanvasRegionPlacement {
        let side = max(region.width, region.height)
        let clamped = clampPair(side, side, locked: true, ratio: 1)
        let centerX = region.origin.x + region.width / 2
        let centerY = region.origin.y + region.height / 2
        return CanvasRegionPlacement(
            origin: MindMapPoint(x: centerX - clamped.width / 2, y: centerY - clamped.height / 2),
            width: clamped.width,
            height: clamped.height
        )
    }

    /// True when `inner` lies entirely inside `outer`, with a small edge tolerance.
    public static func encloses(_ inner: CGRect, in outer: CGRect) -> Bool {
        guard inner.width >= 0, inner.height >= 0, outer.width > 0, outer.height > 0 else { return false }
        guard inner.minX.isFinite, inner.minY.isFinite, outer.minX.isFinite, outer.minY.isFinite else { return false }
        let slack = CanvasRegionLimits.enclosureEpsilon
        return inner.minX >= outer.minX - slack
            && inner.minY >= outer.minY - slack
            && inner.maxX <= outer.maxX + slack
            && inner.maxY <= outer.maxY + slack
    }

    /// The region that wraps every node frame fully inside `region`.
    /// Partial overlaps are left out. Nil when nothing is enclosed, so the caller
    /// does not collapse the region. This does not choose parents.
    public static func fitted(_ region: CanvasRegion, around frames: [CGRect]) -> CanvasRegionPlacement? {
        let outer = region.bounds
        let inside = frames.filter { encloses($0, in: outer) }
        guard var union = inside.first else { return nil }
        for frame in inside.dropFirst() {
            union = union.union(frame)
        }
        let pad = CanvasRegionLimits.fitPadding
        union = union.insetBy(dx: -pad, dy: -pad)
        var width = Double(union.width)
        var height = Double(union.height)
        let ratio = region.aspectRatio
        if region.aspectLocked, ratio > 0, width > 0, height > 0 {
            if width / height > 1 / ratio {
                height = width * ratio
            } else {
                width = height / ratio
            }
        }
        let clamped = clampPair(width, height, locked: region.aspectLocked, ratio: ratio > 0 ? ratio : nil)
        let centerX = Double(union.midX)
        let centerY = Double(union.midY)
        return CanvasRegionPlacement(
            origin: MindMapPoint(x: centerX - clamped.width / 2, y: centerY - clamped.height / 2),
            width: clamped.width,
            height: clamped.height
        )
    }

    static func clampPair(
        _ width: Double,
        _ height: Double,
        locked: Bool,
        ratio: Double?
    ) -> (width: Double, height: Double) {
        var w = CanvasRegionLimits.clampWidth(width)
        var h = CanvasRegionLimits.clampHeight(height)
        guard locked, let ratio, ratio > 0, ratio.isFinite else { return (w, h) }
        if abs(h - w * ratio) <= 0.01 { return (w, h) }
        if h > w * ratio + 0.01 {
            h = CanvasRegionLimits.clampHeight(w * ratio)
        } else if w > h / ratio + 0.01 {
            w = CanvasRegionLimits.clampWidth(h / ratio)
        }
        return (w, h)
    }
}
