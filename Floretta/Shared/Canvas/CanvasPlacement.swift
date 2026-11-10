import FlorettaCore
import CoreGraphics
import Foundation
import SwiftFlow

/// Hit testing and drag updates on top of `LayoutEngine`.
/// Point hits go through SwiftFlow `getIntersectingNodes`. Later frames get a
/// higher `zIndex`, which matches painting the later node on top.
enum CanvasPlacement {
    static let engine = LayoutEngine(cache: TextMeasurementCache(metrics: CoreTextFontMetrics()))

    static func nodes(in document: MindMapDocument) -> [NodeFrame] {
        engine.layout(document)
    }

    static func contentBounds(in document: MindMapDocument, includingStickies: Bool = true) -> CGRect? {
        let placed = nodes(in: document)
        var bounds = placed.first?.frame
        for node in placed.dropFirst() {
            bounds = bounds?.union(node.frame) ?? node.frame
        }
        if includingStickies {
            for sticky in document.stickies {
                let rect = stickyCanvasRect(sticky)
                bounds = bounds?.union(rect) ?? rect
            }
        }
        if !document.relationships.isEmpty {
            for line in RelationshipGeometry.lines(for: document.relationships, frames: placed) {
                bounds = bounds?.union(line.bounds) ?? line.bounds
            }
        }
        return bounds
    }

    static func stickyCanvasRect(_ sticky: StickyNote) -> CGRect {
        CGRect(
            x: sticky.origin.x,
            y: sticky.origin.y,
            width: sticky.width,
            height: sticky.height
        )
    }

    static func nodeID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        hit(at: canvasPoint, in: nodes(in: document), rootsOnly: false)
    }

    /// Topmost root whose frame contains the canvas point. Children are not draggable.
    static func rootID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        hit(at: canvasPoint, in: nodes(in: document), rootsOnly: true)
    }

    /// A hierarchy root, or a free node. Tree children are not draggable.
    static func draggableID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        hit(at: canvasPoint, in: nodes(in: document), rootsOnly: false, draggableOnly: true)
    }

    static func hit(at canvasPoint: CGPoint, in frames: [NodeFrame], rootsOnly: Bool) -> UUID? {
        hit(at: canvasPoint, in: frames, rootsOnly: rootsOnly, draggableOnly: false)
    }

    static func hit(
        at canvasPoint: CGPoint,
        in frames: [NodeFrame],
        rootsOnly: Bool,
        draggableOnly: Bool
    ) -> UUID? {
        let flowNodes = frames.enumerated().map { index, frame in
            Node(
                id: frame.id.uuidString,
                position: XYPosition(x: frame.origin.x, y: frame.origin.y),
                data: FlowHit(id: frame.id, isRoot: frame.isRoot, isFree: frame.isFree),
                width: max(frame.size.width, 0.01),
                height: max(frame.size.height, 0.01),
                zIndex: index
            )
        }
        let probe = Node(
            id: "probe",
            position: XYPosition(x: canvasPoint.x, y: canvasPoint.y),
            data: FlowHit(id: UUID(), isRoot: false, isFree: false),
            width: 0.01,
            height: 0.01,
            zIndex: -1
        )
        let hits = getIntersectingNodes(node: probe, nodes: flowNodes)
        return hits
            .filter { hit in
                if rootsOnly { return hit.data.isRoot }
                if draggableOnly { return hit.data.isRoot || hit.data.isFree }
                return true
            }
            .max { $0.zIndex < $1.zIndex }?
            .data.id
    }

    /// Nodes whose frames overlap `viewport` in canvas coordinates.
    /// Uses SwiftFlow `getIntersectingNodes`.
    static func frames(_ frames: [NodeFrame], intersectingCanvas viewport: CGRect) -> [NodeFrame] {
        let ids = intersectingIDs(frames.map { ($0.id, $0.frame) }, viewport: viewport)
        return frames.filter { ids.contains($0.id) }
    }

    /// Nodes whose link curves overlap `viewport`, including curves that cross the view
    /// while the node itself sits outside it.
    static func nodeIDsWithVisibleLinks(_ frames: [NodeFrame], viewport: CGRect) -> Set<UUID> {
        let boxes = frames.compactMap { frame -> (UUID, CGRect)? in
            guard let link = frame.link else { return nil }
            return (frame.id, curveBounds(link))
        }
        return intersectingIDs(boxes, viewport: viewport)
    }

    static func curveBounds(_ link: LinkCurve) -> CGRect {
        let xs = [link.start.x, link.control1.x, link.control2.x, link.end.x]
        let ys = [link.start.y, link.control1.y, link.control2.y, link.end.y]
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let maxX = xs.max() ?? minX
        let maxY = ys.max() ?? minY
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    }

    private static func intersectingIDs(_ boxes: [(UUID, CGRect)], viewport: CGRect) -> Set<UUID> {
        guard viewport.width > 0, viewport.height > 0,
              viewport.minX.isFinite, viewport.minY.isFinite else { return [] }
        let nodes = boxes.enumerated().map { index, box in
            Node(
                id: box.0.uuidString,
                position: XYPosition(x: box.1.minX, y: box.1.minY),
                data: FlowHit(id: box.0, isRoot: false, isFree: false),
                width: max(box.1.width, 0.01),
                height: max(box.1.height, 0.01),
                zIndex: index
            )
        }
        let probe = Node(
            id: "viewport",
            position: XYPosition(x: viewport.minX, y: viewport.minY),
            data: FlowHit(id: UUID(), isRoot: false, isFree: false),
            width: max(viewport.width, 0.01),
            height: max(viewport.height, 0.01),
            zIndex: -1
        )
        return Set(getIntersectingNodes(node: probe, nodes: nodes).map(\.data.id))
    }

    static func movingRoot(
        _ id: UUID,
        to origin: CGPoint,
        in document: MindMapDocument
    ) -> MindMapDocument {
        var copy = document
        copy.roots = copy.roots.map { root in
            guard root.id == id else { return root }
            var updated = root
            updated.position = MindMapPoint(x: Double(origin.x), y: Double(origin.y))
            return updated
        }
        return copy
    }

    /// Moves a free node by its stored point, or a root when the id is not free.
    /// Layout reads that point back, so the frame is not snapped to a tree slot.
    static func movingNode(
        _ id: UUID,
        to origin: CGPoint,
        in document: MindMapDocument
    ) -> MindMapDocument {
        var copy = document
        let point = MindMapPoint(x: Double(origin.x), y: Double(origin.y))
        if copy.moveFreeNode(id, to: point) {
            return copy
        }
        return movingRoot(id, to: origin, in: document)
    }
}

/// Screen point size for both the canvas glyphs and the editing text view.
/// `styledText` and `editField` must call this, not a second formula.
enum CanvasTextScale {
    static func onScreenPointSize(fontSize: CGFloat, scale: CGFloat) -> CGFloat {
        let safeFont = fontSize.isFinite ? max(fontSize, 1) : 1
        return safeFont * CanvasViewport.clampScale(scale)
    }
}

/// Text level from the on-screen point size. Below 9pt the node is a color block.
enum CanvasTextLOD: Equatable, Sendable {
    case blocks
    case title
    case full

    var drawsTitle: Bool { self != .blocks }

    static func level(onScreenPointSize: CGFloat) -> CanvasTextLOD {
        guard onScreenPointSize.isFinite else { return .blocks }
        if onScreenPointSize < 9 { return .blocks }
        if onScreenPointSize < 14 { return .title }
        return .full
    }
}

/// How much of a node's style to paint. Driven by zoom and the node's on-screen size.
enum CanvasDetail: Equatable, Sendable {
    /// Color blocks and links only.
    case far
    /// Text on. Shadows and hairline borders stay off.
    case mid
    /// Full style: text, strokes, shadows, and selection handles.
    case near

    var drawsText: Bool { self != .far }
    var drawsShadow: Bool { self == .near }
    var drawsFineBorder: Bool { self == .near }
    var drawsSelectionHandles: Bool { self == .near }

    static func level(scale: CGFloat, onScreenHeight: CGFloat) -> CanvasDetail {
        guard scale.isFinite, onScreenHeight.isFinite else { return .far }
        if onScreenHeight < 8 { return .far }
        if scale >= 1, onScreenHeight >= 12 { return .near }
        if onScreenHeight >= 28 { return .near }
        if onScreenHeight >= 10 || scale >= 0.75 { return .mid }
        return .far
    }
}

enum CanvasDrawPolicy {
    /// Documents this large draw every link as a straight segment.
    static let straightLinkNodeThreshold = 400
    /// Canvas-space length past which one link is drawn straight.
    static let longLinkLength: CGFloat = 720

    static func useStraightLink(nodeCount: Int, link: LinkCurve) -> Bool {
        if nodeCount >= straightLinkNodeThreshold { return true }
        return hypot(link.end.x - link.start.x, link.end.y - link.start.y) >= longLinkLength
    }
}

private struct FlowHit: Equatable, Sendable {
    var id: UUID
    var isRoot: Bool
    var isFree: Bool
}
