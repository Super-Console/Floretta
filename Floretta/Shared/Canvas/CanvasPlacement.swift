import CoreGraphics
import Foundation

/// Hit testing and drag updates on top of `LayoutEngine`.
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
        for node in nodes(in: document).reversed() where node.frame.contains(canvasPoint) {
            return node.id
        }
        return nil
    }

    /// Topmost root whose frame contains the canvas point. Children are not draggable.
    static func rootID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        for node in nodes(in: document).reversed() where node.isRoot && node.frame.contains(canvasPoint) {
            return node.id
        }
        return nil
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
