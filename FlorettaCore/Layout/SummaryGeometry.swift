import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The summary topic and the bracket beside the topics it covers.
/// Built from `TopicSummary` plus laid-out frames. Nothing here is stored.
public struct SummaryMark: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var parentID: UUID
    public var text: String
    public var topicRect: CGRect
    public var braceTop: CGPoint
    public var braceMid: CGPoint
    public var braceBottom: CGPoint
    public var bounds: CGRect

    public init(
        id: UUID,
        parentID: UUID,
        text: String,
        topicRect: CGRect,
        braceTop: CGPoint,
        braceMid: CGPoint,
        braceBottom: CGPoint,
        bounds: CGRect
    ) {
        self.id = id
        self.parentID = parentID
        self.text = text
        self.topicRect = topicRect
        self.braceTop = braceTop
        self.braceMid = braceMid
        self.braceBottom = braceBottom
        self.bounds = bounds
    }
}

/// The rounded enclosure around the topics a boundary covers.
public struct BoundaryMark: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var parentID: UUID
    public var title: String
    public var rect: CGRect
    public var titleRect: CGRect
    public var bounds: CGRect

    public init(id: UUID, parentID: UUID, title: String, rect: CGRect, titleRect: CGRect, bounds: CGRect) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.rect = rect
        self.titleRect = titleRect
        self.bounds = bounds
    }
}

/// Brackets and enclosures for summaries and boundaries on the first sheet.
/// Collapsed topics have no frames, so their marks are skipped until they open.
public enum SummaryGeometry {
    public static let summaryInk = BranchColor(red: 0.45, green: 0.32, blue: 0.62)
    public static let boundaryInk = BranchColor(red: 0.29, green: 0.42, blue: 0.62)
    public static let topicFontSize: CGFloat = 16
    public static let titleFontSize: CGFloat = 12
    public static let lineWidth: CGFloat = 1.5
    public static let cornerRadius: CGFloat = 10

    public static func summaries(in document: MindMapDocument, frames: [NodeFrame]) -> [SummaryMark] {
        guard document.hasSummaries, !frames.isEmpty else { return [] }
        let index = FrameIndex(frames)
        var marks: [SummaryMark] = []
        walk(document) { node in
            guard !node.summaries.isEmpty else { return }
            for summary in node.summaries {
                guard let covered = coveredIDs(node, summary.rangeStart, summary.rangeEnd),
                      let union = index.union(of: covered) else { continue }
                marks.append(makeSummary(summary, parentID: node.id, union: union, parentRect: index.rects[node.id]))
            }
        }
        return marks
    }

    public static func boundaries(in document: MindMapDocument, frames: [NodeFrame]) -> [BoundaryMark] {
        guard document.hasBoundaries, !frames.isEmpty else { return [] }
        let index = FrameIndex(frames)
        var marks: [BoundaryMark] = []
        walk(document) { node in
            guard !node.boundaries.isEmpty else { return }
            for boundary in node.boundaries {
                guard let covered = coveredIDs(node, boundary.rangeStart, boundary.rangeEnd),
                      let union = index.union(of: covered) else { continue }
                marks.append(makeBoundary(boundary, parentID: node.id, union: union))
            }
        }
        return marks
    }

    public static func summaryHit(at point: CGPoint, in marks: [SummaryMark]) -> UUID? {
        for mark in marks.reversed() {
            if mark.topicRect.insetBy(dx: -4, dy: -4).contains(point) { return mark.id }
            if segmentDistance(point, mark.braceTop, mark.braceMid) <= 8 { return mark.id }
            if segmentDistance(point, mark.braceMid, mark.braceBottom) <= 8 { return mark.id }
        }
        return nil
    }

    public static func boundaryHit(at point: CGPoint, in marks: [BoundaryMark]) -> UUID? {
        for mark in marks.reversed() {
            if mark.titleRect.width > 0, mark.titleRect.insetBy(dx: -2, dy: -2).contains(point) {
                return mark.id
            }
            if onStroke(point, of: mark.rect) { return mark.id }
        }
        return nil
    }

    public static func topicSize(text: String) -> CGSize {
        let glyphs = max(text.count, 2)
        let width = min(CGFloat(glyphs) * topicFontSize + 20, 280)
        return CGSize(width: max(width, 44), height: topicFontSize + 16)
    }

    private static func makeSummary(
        _ summary: TopicSummary,
        parentID: UUID,
        union: CGRect,
        parentRect: CGRect?
    ) -> SummaryMark {
        let side: CGFloat
        if let parentRect {
            side = union.midX >= parentRect.midX ? 1 : -1
        } else {
            side = 1
        }
        let x = side > 0 ? union.maxX + 12 : union.minX - 12
        let top = CGPoint(x: x, y: union.minY)
        let mid = CGPoint(x: x + side * 16, y: union.midY)
        let bottom = CGPoint(x: x, y: union.maxY)
        let size = topicSize(text: summary.text)
        let topic = CGRect(
            x: side > 0 ? mid.x + 18 : mid.x - 18 - size.width,
            y: union.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        var bounds = topic
        for point in [top, mid, bottom] {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return SummaryMark(
            id: summary.id,
            parentID: parentID,
            text: summary.text,
            topicRect: topic,
            braceTop: top,
            braceMid: mid,
            braceBottom: bottom,
            bounds: bounds
        )
    }

    private static func makeBoundary(_ boundary: TopicBoundary, parentID: UUID, union: CGRect) -> BoundaryMark {
        let rect = union.insetBy(dx: -14, dy: -14)
        let titleSize = boundary.title.isEmpty
            ? CGSize.zero
            : CGSize(width: min(CGFloat(boundary.title.count) * titleFontSize + 12, 240), height: titleFontSize + 6)
        let titleRect = CGRect(
            x: rect.midX - titleSize.width / 2,
            y: rect.minY - titleSize.height / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        return BoundaryMark(
            id: boundary.id,
            parentID: parentID,
            title: boundary.title,
            rect: rect,
            titleRect: titleRect,
            bounds: rect.union(titleRect)
        )
    }

    private static func coveredIDs(_ node: MindMapNode, _ start: Int, _ end: Int) -> [UUID]? {
        guard start >= 0, end >= start, end < node.children.count else { return nil }
        return node.children[start...end].map(\.id)
    }

    private static func walk(_ document: MindMapDocument, _ visit: (MindMapNode) -> Void) {
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                visit(node)
                walk(node.children)
            }
        }
        walk(document.roots)
        walk(document.freeNodes)
    }

    private static func segmentDistance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.01 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let x = start.x + t * dx
        let y = start.y + t * dy
        return hypot(point.x - x, point.y - y)
    }

    private static func onStroke(_ point: CGPoint, of rect: CGRect) -> Bool {
        let outer = rect.insetBy(dx: -8, dy: -8)
        guard outer.contains(point) else { return false }
        let inner = rect.insetBy(dx: 8, dy: 8)
        if inner.width <= 0 || inner.height <= 0 { return true }
        return !inner.contains(point)
    }
}

private struct FrameIndex {
    var rects: [UUID: CGRect]
    var children: [UUID: [UUID]]

    init(_ frames: [NodeFrame]) {
        rects = [:]
        children = [:]
        rects.reserveCapacity(frames.count)
        for frame in frames {
            rects[frame.id] = frame.rect
            if let parentID = frame.parentID {
                children[parentID, default: []].append(frame.id)
            }
        }
    }

    func union(of roots: [UUID]) -> CGRect? {
        var stack = roots
        var seen: Set<UUID> = []
        var box: CGRect?
        while let id = stack.popLast() {
            if !seen.insert(id).inserted { continue }
            if let rect = rects[id] {
                box = box?.union(rect) ?? rect
            }
            if let kids = children[id] {
                stack.append(contentsOf: kids)
            }
        }
        guard let box, box.width > 0, box.height > 0 else { return nil }
        return box
    }
}
