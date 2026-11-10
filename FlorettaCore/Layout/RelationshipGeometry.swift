import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One drawn relationship. Built from `TopicRelationship` plus the frames layout
/// already produced. Nothing here is stored in the document: the record stays
/// `TopicRelationship`, and `NodeFrame.link` stays the parent/child curve.
public struct RelationshipLine: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourceID: UUID
    public var targetID: UUID
    public var title: String
    public var curve: LinkCurve
    /// Label anchor when the curve is drawn.
    public var curveLabel: CGPoint
    /// Label anchor when the drawer flattens the curve to a segment.
    public var chordLabel: CGPoint
    public var labelSize: CGSize

    public init(
        id: UUID,
        sourceID: UUID,
        targetID: UUID,
        title: String,
        curve: LinkCurve,
        curveLabel: CGPoint,
        chordLabel: CGPoint,
        labelSize: CGSize
    ) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.title = title
        self.curve = curve
        self.curveLabel = curveLabel
        self.chordLabel = chordLabel
        self.labelSize = labelSize
    }

    public func labelCenter(straight: Bool) -> CGPoint {
        straight ? chordLabel : curveLabel
    }

    public var bounds: CGRect {
        var box = RelationshipGeometry.curveBounds(curve)
        box = box.union(Self.labelRect(center: curveLabel, size: labelSize))
        box = box.union(Self.labelRect(center: chordLabel, size: labelSize))
        return box
    }

    public static func labelRect(center: CGPoint, size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return CGRect(x: center.x, y: center.y, width: 0, height: 0)
        }
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Curves for `MindMapDocument.relationships`. Endpoints come from laid-out
/// topic frames, so a collapsed or focused-away topic simply has no line.
public enum RelationshipGeometry {
    /// Distinct from the branch palette so a relationship does not read as a child link.
    public static let ink = BranchColor(red: 0.11, green: 0.46, blue: 0.50)
    public static let lineWidth: CGFloat = 2
    public static let labelFontSize: CGFloat = 13
    public static let hitSlop: CGFloat = 10

    public static func lines(in document: MindMapDocument, frames: [NodeFrame]) -> [RelationshipLine] {
        lines(for: document.relationships, frames: frames)
    }

    public static func lines(for relationships: [TopicRelationship], frames: [NodeFrame]) -> [RelationshipLine] {
        guard !relationships.isEmpty, !frames.isEmpty else { return [] }
        var rects: [UUID: CGRect] = [:]
        if relationships.count > 4, frames.count > 48 {
            rects.reserveCapacity(frames.count)
            for frame in frames {
                rects[frame.id] = frame.rect
            }
        }
        var lines: [RelationshipLine] = []
        lines.reserveCapacity(relationships.count)
        for relationship in relationships {
            let source = rects[relationship.sourceID] ?? frames.first { $0.id == relationship.sourceID }?.rect
            let target = rects[relationship.targetID] ?? frames.first { $0.id == relationship.targetID }?.rect
            guard let source, let target, let line = make(relationship, from: source, to: target) else { continue }
            lines.append(line)
        }
        return lines
    }

    /// Later lines win. `straight` must match the segment the canvas actually strokes.
    public static func hit(
        at point: CGPoint,
        in lines: [RelationshipLine],
        straight: (RelationshipLine) -> Bool = { _ in false },
        slop: CGFloat = hitSlop
    ) -> UUID? {
        guard point.x.isFinite, point.y.isFinite, slop.isFinite, slop > 0 else { return nil }
        let slopSquared = slop * slop
        for line in lines.reversed() {
            let label = RelationshipLine.labelRect(center: line.labelCenter(straight: straight(line)), size: line.labelSize)
            if label.insetBy(dx: -slop, dy: -slop).contains(point) {
                return line.id
            }
            if nearestDistanceSquared(point, curve: line.curve, straight: straight(line)) <= slopSquared {
                return line.id
            }
        }
        return nil
    }

    public static func curveBounds(_ curve: LinkCurve) -> CGRect {
        let xs = [curve.start.x, curve.control1.x, curve.control2.x, curve.end.x]
        let ys = [curve.start.y, curve.control1.y, curve.control2.y, curve.end.y]
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let maxX = xs.max() ?? minX
        let maxY = ys.max() ?? minY
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    }

    /// Tip is `tip`. The head points from `from` toward `tip`.
    public static func arrow(tip: CGPoint, from: CGPoint, length: CGFloat = 9) -> (left: CGPoint, right: CGPoint) {
        let dx = tip.x - from.x
        let dy = tip.y - from.y
        let span = max(hypot(dx, dy), 0.01)
        let ux = dx / span
        let uy = dy / span
        let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
        let px = -uy * length * 0.45
        let py = ux * length * 0.45
        return (
            left: CGPoint(x: base.x + px, y: base.y + py),
            right: CGPoint(x: base.x - px, y: base.y - py)
        )
    }

    public static func labelSize(title: String) -> CGSize {
        guard !title.isEmpty else { return .zero }
        let width = min(CGFloat(title.count) * labelFontSize + 16, 360)
        return CGSize(width: max(width, 28), height: labelFontSize + 10)
    }

    private static func make(_ relationship: TopicRelationship, from source: CGRect, to target: CGRect) -> RelationshipLine? {
        let start = boundaryPoint(of: source, toward: CGPoint(x: target.midX, y: target.midY))
        let end = boundaryPoint(of: target, toward: CGPoint(x: source.midX, y: source.midY))
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 1, length.isFinite else { return nil }
        let bow = min(56, max(18, length * 0.22))
        let px = -dy / length
        let py = dx / length
        let chordLabel = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bowed = CGPoint(x: chordLabel.x + px * bow, y: chordLabel.y + py * bow)
        let control1 = CGPoint(
            x: start.x + (bowed.x - start.x) * 0.65,
            y: start.y + (bowed.y - start.y) * 0.65
        )
        let control2 = CGPoint(
            x: end.x + (bowed.x - end.x) * 0.65,
            y: end.y + (bowed.y - end.y) * 0.65
        )
        let curve = LinkCurve(
            start: start,
            control1: control1,
            control2: control2,
            end: end,
            lineWidth: lineWidth,
            color: ink
        )
        return RelationshipLine(
            id: relationship.id,
            sourceID: relationship.sourceID,
            targetID: relationship.targetID,
            title: relationship.title,
            curve: curve,
            curveLabel: point(on: curve, t: 0.5),
            chordLabel: chordLabel,
            labelSize: labelSize(title: relationship.title)
        )
    }

    private static func boundaryPoint(of rect: CGRect, toward other: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = other.x - center.x
        let dy = other.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let halfW = max(rect.width / 2, 0.01)
        let halfH = max(rect.height / 2, 0.01)
        let sx = abs(dx) < 0.0001 ? CGFloat.greatestFiniteMagnitude : halfW / abs(dx)
        let sy = abs(dy) < 0.0001 ? CGFloat.greatestFiniteMagnitude : halfH / abs(dy)
        let scale = min(sx, sy)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    private static func point(on curve: LinkCurve, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return CGPoint(
            x: uu * u * curve.start.x + 3 * uu * t * curve.control1.x + 3 * u * tt * curve.control2.x + tt * t * curve.end.x,
            y: uu * u * curve.start.y + 3 * uu * t * curve.control1.y + 3 * u * tt * curve.control2.y + tt * t * curve.end.y
        )
    }

    private static func nearestDistanceSquared(_ point: CGPoint, curve: LinkCurve, straight: Bool) -> CGFloat {
        if straight {
            return segmentDistanceSquared(point, curve.start, curve.end)
        }
        var previous = curve.start
        var best = CGFloat.greatestFiniteMagnitude
        let steps = 16
        for step in 1...steps {
            let sample = self.point(on: curve, t: CGFloat(step) / CGFloat(steps))
            best = min(best, segmentDistanceSquared(point, previous, sample))
            previous = sample
        }
        return best
    }

    private static func segmentDistanceSquared(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t: CGFloat
        if len2 < 0.0001 {
            t = 0
        } else {
            let raw = ((point.x - a.x) * dx + (point.y - a.y) * dy) / len2
            t = min(max(raw, 0), 1)
        }
        let x = a.x + t * dx
        let y = a.y + t * dy
        let ox = point.x - x
        let oy = point.y - y
        return ox * ox + oy * oy
    }
}
