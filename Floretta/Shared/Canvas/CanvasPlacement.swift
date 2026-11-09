import CoreGraphics
import Foundation

enum NodeMetrics {
    static func size(for text: String) -> CGSize {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let lineCount = max(1, lines.count)
        let longest = lines.map(\.count).max() ?? text.count
        let width = min(320, max(96, CGFloat(longest) * 12 + 32))
        let height = max(36, CGFloat(lineCount) * 22 + 14)
        return CGSize(width: width, height: height)
    }
}

struct PlacedNode: Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var frame: CGRect
    var isRoot: Bool
    var parentID: UUID?
}

/// Where nodes sit on the canvas.
/// Roots use a stored position, or a simple row if they have never been dragged.
/// Children without a stored position sit to the right of the parent so the tree is visible.
/// That offset is not the P1-2 left/right layout.
enum CanvasPlacement {
    static let rootSpacing: CGFloat = 240
    static let childGapX: CGFloat = 36
    static let childGapY: CGFloat = 12

    static func nodes(in document: MindMapDocument) -> [PlacedNode] {
        var placed: [PlacedNode] = []
        for (index, root) in document.roots.enumerated() {
            let origin = CGPoint(
                x: CGFloat(root.position?.x ?? Double(index) * Double(rootSpacing)),
                y: CGFloat(root.position?.y ?? 0)
            )
            append(root, origin: origin, isRoot: true, parentID: nil, into: &placed)
        }
        return placed
    }

    static func contentBounds(in document: MindMapDocument) -> CGRect? {
        let placed = nodes(in: document)
        guard var bounds = placed.first?.frame else { return nil }
        for node in placed.dropFirst() {
            bounds = bounds.union(node.frame)
        }
        return bounds
    }

    /// Topmost root whose frame contains the canvas point. Children are not draggable.
    static func rootID(at canvasPoint: CGPoint, in document: MindMapDocument) -> UUID? {
        for node in nodes(in: document).reversed() where node.isRoot {
            if node.frame.contains(canvasPoint) {
                return node.id
            }
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

    private static func append(
        _ node: MindMapNode,
        origin: CGPoint,
        isRoot: Bool,
        parentID: UUID?,
        into placed: inout [PlacedNode]
    ) {
        let frame = CGRect(origin: origin, size: NodeMetrics.size(for: node.text))
        placed.append(
            PlacedNode(
                id: node.id,
                text: node.text,
                frame: frame,
                isRoot: isRoot,
                parentID: parentID
            )
        )
        for (index, child) in node.children.enumerated() {
            let childOrigin: CGPoint
            if let position = child.position {
                childOrigin = CGPoint(x: position.x, y: position.y)
            } else {
                let childSize = NodeMetrics.size(for: child.text)
                childOrigin = CGPoint(
                    x: frame.maxX + childGapX,
                    y: frame.minY + CGFloat(index) * (childSize.height + childGapY)
                )
            }
            append(child, origin: childOrigin, isRoot: false, parentID: node.id, into: &placed)
        }
    }
}
