import CoreGraphics
import Foundation
import FlorettaCore

enum SelectionMove: String, Equatable, Sendable {
    case up
    case down
    case left
    case right
}

/// Arrow targets from laid-out frames.
///
/// Up and down stay on siblings that share the current node's side of the parent. A bilateral
/// root centers a lone child on the other side between the stacked pair, so that child is closer
/// in Y and must not steal the move. Distance is each candidate's own midY against the current
/// node, not the parent's midY.
/// Left and right prefer this node's own children on that side, and among those pick the nearest
/// by vertical distance, then horizontal distance. If there is no child on that side, the parent
/// is used when the parent lies on that side. Otherwise the move crosses branches and picks the
/// nearest other frame on that side with the same distance rule.
enum SelectionNavigator {
    static func destination(from id: UUID, move: SelectionMove, frames: [NodeFrame]) -> UUID? {
        guard let node = frames.first(where: { $0.id == id }) else { return nil }
        switch move {
        case .up:
            return sibling(of: node, in: frames, above: true)
        case .down:
            return sibling(of: node, in: frames, above: false)
        case .left:
            return horizontal(from: node, in: frames, towardLeft: true)
        case .right:
            return horizontal(from: node, in: frames, towardLeft: false)
        }
    }

    private static func sibling(of node: NodeFrame, in frames: [NodeFrame], above: Bool) -> UUID? {
        let siblings = frames.filter { $0.parentID == node.parentID && $0.id != node.id }
        let column = siblings.filter { sameSide($0, as: node, in: frames) }
        let candidates = column.filter { candidate in
            above
                ? candidate.frame.midY < node.frame.midY - 0.5
                : candidate.frame.midY > node.frame.midY + 0.5
        }
        return nearest(candidates, to: node)?.id
    }

    /// Roots stack in one column. Children are split by which side of the parent they sit on.
    private static func sameSide(_ candidate: NodeFrame, as node: NodeFrame, in frames: [NodeFrame]) -> Bool {
        guard let parentID = node.parentID,
              let parent = frames.first(where: { $0.id == parentID }) else {
            return true
        }
        let nodeDX = node.frame.midX - parent.frame.midX
        let candidateDX = candidate.frame.midX - parent.frame.midX
        if abs(nodeDX) <= 0.5 || abs(candidateDX) <= 0.5 {
            return abs(nodeDX) <= 0.5 && abs(candidateDX) <= 0.5
        }
        return (nodeDX > 0) == (candidateDX > 0)
    }

    private static func horizontal(from node: NodeFrame, in frames: [NodeFrame], towardLeft: Bool) -> UUID? {
        let children = frames.filter { $0.parentID == node.id }
        let onSide = children.filter { isOnSide($0, of: node, towardLeft: towardLeft) }
        if let child = nearest(onSide, to: node) {
            return child.id
        }
        if let parent = frames.first(where: { $0.id == node.parentID }),
           isOnSide(parent, of: node, towardLeft: towardLeft) {
            return parent.id
        }
        let others = frames.filter { candidate in
            candidate.id != node.id && isOnSide(candidate, of: node, towardLeft: towardLeft)
        }
        return nearest(others, to: node)?.id
    }

    private static func isOnSide(_ candidate: NodeFrame, of node: NodeFrame, towardLeft: Bool) -> Bool {
        towardLeft
            ? candidate.frame.midX < node.frame.midX - 0.5
            : candidate.frame.midX > node.frame.midX + 0.5
    }

    /// Nearest row first, then the closer column. Stable id order breaks a remaining tie.
    private static func nearest(_ candidates: [NodeFrame], to node: NodeFrame) -> NodeFrame? {
        candidates.min { lhs, rhs in
            let leftY = abs(lhs.frame.midY - node.frame.midY)
            let rightY = abs(rhs.frame.midY - node.frame.midY)
            if abs(leftY - rightY) > 0.001 {
                return leftY < rightY
            }
            let leftX = abs(lhs.frame.midX - node.frame.midX)
            let rightX = abs(rhs.frame.midX - node.frame.midX)
            if abs(leftX - rightX) > 0.001 {
                return leftX < rightX
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
