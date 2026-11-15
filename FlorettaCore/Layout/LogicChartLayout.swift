import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 逻辑图: the root sits at the left and every branch grows right.
///
/// One rule drives the whole structure: a topic is vertically centered on the
/// stack of its children, and each child is one `horizontalGap` to the right of
/// its parent. Siblings are `siblingGap` apart. Nothing is mirrored, so the
/// reading order is top to bottom on a single rightward axis.
public struct LogicChartLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .logicChart }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    /// A topic with its subtree already measured along the vertical axis.
    private struct Block {
        var node: MindMapNode
        var size: CGSize
        var children: [Block]
        /// Height of this topic and every descendant, sibling gaps included.
        var stackHeight: CGFloat
        var depth: Int
        var branch: BranchColor
    }

    public func place(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        for root in document.roots {
            geometry.collectHeights(root, depth: 0, into: &levelHeights)
        }
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        var placedAutoRoot = false
        for root in document.roots {
            let block = measure(root, depth: 0, branch: .black, heights: levelHeights)
            let nodeOrigin: CGPoint
            if let position = root.position {
                // A dragged root keeps the point the user dropped it on. Its
                // subtree still follows, so the map stays readable.
                nodeOrigin = CGPoint(x: position.x, y: position.y)
            } else {
                let top = placedAutoRoot ? nextTop : 0
                nodeOrigin = CGPoint(
                    x: 0,
                    y: top + (block.stackHeight - block.size.height) / 2
                )
            }
            let rootFrame = frame(for: block, origin: nodeOrigin, parentID: nil, link: nil)
            frames.append(rootFrame)
            placeChildren(of: block, under: rootFrame, into: &frames)
            // Next root starts below this block, whichever origin it used.
            let blockTop = rootFrame.rect.midY - block.stackHeight / 2
            nextTop = blockTop + block.stackHeight + geometry.metrics.siblingGap * 2
            placedAutoRoot = true
        }
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    private func frame(
        for block: Block,
        origin: CGPoint,
        parentID: UUID?,
        link: LinkCurve?
    ) -> NodeFrame {
        geometry.frame(
            node: block.node,
            origin: origin,
            size: block.size,
            depth: block.depth,
            isRoot: block.depth == 0,
            parentID: parentID,
            branch: block.branch,
            link: link,
            childBadgeInset: block.depth > 0 ? geometry.appearance.childCountBadgeInset : 0,
            // Children always sit on the right, so the badge slot is never on minX.
            childBadgeOnMinX: false
        )
    }

    private func placeChildren(
        of block: Block,
        under parent: NodeFrame,
        into frames: inout [NodeFrame]
    ) {
        guard !block.children.isEmpty else { return }
        let gaps = geometry.metrics.siblingGap * CGFloat(block.children.count - 1)
        let stack = block.children.reduce(CGFloat(0)) { $0 + $1.stackHeight } + gaps
        var top = parent.rect.midY - stack / 2
        for child in block.children {
            let origin = CGPoint(
                x: parent.rect.maxX + geometry.metrics.horizontalGap,
                y: top + (child.stackHeight - child.size.height) / 2
            )
            let rect = CGRect(origin: origin, size: child.size)
            let childFrame = frame(
                for: child,
                origin: origin,
                parentID: parent.id,
                link: geometry.link(
                    from: parent.rect,
                    to: rect,
                    anchor: .right,
                    depth: child.depth,
                    color: child.branch
                )
            )
            frames.append(childFrame)
            placeChildren(of: child, under: childFrame, into: &frames)
            top += child.stackHeight + geometry.metrics.siblingGap
        }
    }

    private func measure(
        _ node: MindMapNode,
        depth: Int,
        branch: BranchColor,
        heights: [Int: CGFloat]
    ) -> Block {
        let size = geometry.size(
            node,
            depth: depth,
            heights: heights,
            reservesChildBadge: depth > 0 && geometry.appearance.childCountBadgeInset > 0
        )
        let kids = node.isCollapsed ? [] : node.children.filter { $0.position == nil }
        let children = kids.map { child in
            measure(
                child,
                depth: depth + 1,
                branch: geometry.appearance.palette.color(at: geometry.childIndex(of: child, in: node)),
                heights: heights
            )
        }
        let gaps = geometry.metrics.siblingGap * CGFloat(max(children.count - 1, 0))
        let stack = children.reduce(CGFloat(0)) { $0 + $1.stackHeight } + gaps
        return Block(
            node: node,
            size: size,
            children: children,
            stackHeight: max(size.height, stack),
            depth: depth,
            branch: branch
        )
    }
}
