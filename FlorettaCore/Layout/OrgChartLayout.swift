import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 组织结构图: the root sits at the top and every branch grows downward.
///
/// The mirror of the logic chart on the other axis: a topic is horizontally
/// centered on the row of its children, and each child row is one
/// `horizontalGap` below its parent. Siblings are `siblingGap` apart.
public struct OrgChartLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .orgChart }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    /// A topic with its subtree measured along the horizontal axis.
    private struct Block {
        var node: MindMapNode
        var size: CGSize
        var children: [Block]
        /// Width of this topic and every descendant, sibling gaps included.
        var stackWidth: CGFloat
        /// Height of the topic plus, when it has children, the gap and the child rows.
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
            let top: CGFloat
            let centerX: CGFloat
            if let position = root.position {
                // A dragged root keeps the point the user dropped it on, and its
                // subtree stays centered under it.
                top = position.y
                centerX = position.x + block.size.width / 2
            } else {
                top = placedAutoRoot ? nextTop : 0
                centerX = 0
            }
            let rootFrame = frame(
                for: block,
                origin: CGPoint(x: centerX - block.size.width / 2, y: top),
                parentID: nil,
                link: nil
            )
            frames.append(rootFrame)
            placeChildren(of: block, under: rootFrame, into: &frames)
            nextTop = top + block.stackHeight + geometry.metrics.siblingGap * 2
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
            // Children spread on both sides, so neither edge owns the badge slot.
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
        let row = block.children.reduce(CGFloat(0)) { $0 + $1.stackWidth } + gaps
        var left = parent.rect.midX - row / 2
        for child in block.children {
            let origin = CGPoint(
                x: left + (child.stackWidth - child.size.width) / 2,
                y: parent.rect.maxY + geometry.metrics.horizontalGap
            )
            let rect = CGRect(origin: origin, size: child.size)
            let childFrame = frame(
                for: child,
                origin: origin,
                parentID: parent.id,
                link: geometry.link(
                    from: parent.rect,
                    to: rect,
                    anchor: .down,
                    depth: child.depth,
                    color: child.branch
                )
            )
            frames.append(childFrame)
            placeChildren(of: child, under: childFrame, into: &frames)
            left += child.stackWidth + geometry.metrics.siblingGap
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
        let row = children.reduce(CGFloat(0)) { $0 + $1.stackWidth } + gaps
        let rowHeight = children.map(\.stackHeight).max() ?? 0
        let below = children.isEmpty ? 0 : geometry.metrics.horizontalGap + rowHeight
        return Block(
            node: node,
            size: size,
            children: children,
            stackWidth: max(size.width, row),
            stackHeight: size.height + below,
            depth: depth,
            branch: branch
        )
    }
}
