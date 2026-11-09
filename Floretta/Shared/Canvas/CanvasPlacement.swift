import CoreGraphics
import Foundation
import SwiftFlow

/// Hit testing and drag updates on top of `LayoutEngine`.
/// Point hits go through SwiftFlow `getIntersectingNodes`. Later frames get a
/// higher `zIndex`, which matches painting the later node on top.
enum CanvasPlacement {
    static let engine = LayoutEngine()

    static func nodes(in document: MindMapDocument) -> [NodeFrame] {
        engine.layout(document)
    }

    static func contentBounds(in document: MindMapDocument) -> CGRect? {
        let placed = nodes(in: document)
        guard var bounds = placed.first?.frame else { return nil }
        for node in placed.dropFirst() {
            bounds = bounds.union(node.frame)
        }
        return bounds
    }

    static func nodeID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        hit(at: canvasPoint, in: nodes(in: document), rootsOnly: false)
    }

    /// Topmost root whose frame contains the canvas point. Children are not draggable.
    static func rootID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        hit(at: canvasPoint, in: nodes(in: document), rootsOnly: true)
    }

    static func hit(at canvasPoint: CGPoint, in frames: [NodeFrame], rootsOnly: Bool) -> UUID? {
        let flowNodes = frames.enumerated().map { index, frame in
            Node(
                id: frame.id.uuidString,
                position: XYPosition(x: frame.origin.x, y: frame.origin.y),
                data: FlowHit(id: frame.id, isRoot: frame.isRoot),
                width: max(frame.size.width, 0.01),
                height: max(frame.size.height, 0.01),
                zIndex: index
            )
        }
        let probe = Node(
            id: "probe",
            position: XYPosition(x: canvasPoint.x, y: canvasPoint.y),
            data: FlowHit(id: UUID(), isRoot: false),
            width: 0.01,
            height: 0.01,
            zIndex: -1
        )
        let hits = getIntersectingNodes(node: probe, nodes: flowNodes)
        return hits
            .filter { rootsOnly ? $0.data.isRoot : true }
            .max { $0.zIndex < $1.zIndex }?
            .data.id
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
}

private struct FlowHit: Equatable, Sendable {
    var id: UUID
    var isRoot: Bool
}
