import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 时间轴: one horizontal spine, first-level topics alternate above and
/// below it in sibling order.
///
/// The spine is not a second drawing primitive. Every first-level topic gets a
/// link whose start sits on `axisY`, so the anchors themselves read as the
/// straight line the structure is named for. Deeper levels grow away from the
/// spine as a centered column: a child is one `horizontalGap` past its parent on
/// the same side, siblings are `siblingGap` apart, and every child shares its
/// parent's centre line.
public struct TimelineLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .timeline }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    /// Which side of the spine a subtree grows towards.
    private enum Growth {
        case up
        case down
    }

    /// A topic with its subtree already measured along the spine's normal.
    private struct Block {
        var node: MindMapNode
        var size: CGSize
        var children: [Block]
        /// Widest topic in this column. Stacked nodes share one centre line, so
        /// the slot has to be as wide as the widest of them.
        var columnWidth: CGFloat
        /// Height of the descendant stack, measured from the topic's far edge.
        var tailHeight: CGFloat
        var depth: Int
        var branch: BranchColor
        /// The topic plus every descendant, gaps included.
        var fullHeight: CGFloat { size.height + tailHeight }
    }

    public func place(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        for root in document.roots {
            geometry.collectHeights(root, depth: 0, into: &levelHeights)
        }
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        for root in document.roots {
            let block = measure(root, depth: 0, branch: .black, heights: levelHeights)
            let gap = geometry.metrics.horizontalGap
            var above: CGFloat = 0
            var below: CGFloat = 0
            for (index, event) in block.children.enumerated() {
                if isAbove(index) {
                    above = max(above, gap + event.fullHeight)
                } else {
                    below = max(below, gap + event.fullHeight)
                }
            }
            let axisY: CGFloat
            let origin: CGPoint
            if let position = root.position {
                // A dragged root keeps its point; the spine follows its centre.
                origin = CGPoint(x: position.x, y: position.y)
                axisY = position.y + block.size.height / 2
            } else {
                // `above` is the room the highest branch needs, so the map never
                // starts above y = 0.
                axisY = nextTop + max(above, block.size.height / 2)
                origin = CGPoint(x: 0, y: axisY - block.size.height / 2)
            }
            let rootFrame = frame(for: block, origin: origin, parentID: nil, link: nil)
            frames.append(rootFrame)
            placeEvents(of: block, rootFrame: rootFrame, axisY: axisY, into: &frames)
            let bottom = frames.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
            nextTop = bottom + geometry.metrics.siblingGap * 2
        }
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    /// Even siblings sit above the spine, odd siblings below it.
    private func isAbove(_ index: Int) -> Bool {
        index % 2 == 0
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
            // The spine runs along x, so neither side edge owns the badge slot.
            childBadgeOnMinX: false
        )
    }

    private func placeEvents(
        of block: Block,
        rootFrame: NodeFrame,
        axisY: CGFloat,
        into frames: inout [NodeFrame]
    ) {
        guard !block.children.isEmpty else { return }
        let gap = geometry.metrics.horizontalGap
        var cursor = rootFrame.frame.maxX + gap
        for (index, event) in block.children.enumerated() {
            let origin = CGPoint(
                x: cursor + (event.columnWidth - event.size.width) / 2,
                y: isAbove(index) ? axisY - gap - event.size.height : axisY + gap
            )
            let rect = CGRect(origin: origin, size: event.size)
            // The anchor is a zero-sized rect on the spine, so the shared curve
            // builder starts exactly on the axis line.
            let anchor = CGRect(x: rect.midX, y: axisY, width: 0, height: 0)
            let childFrame = frame(
                for: event,
                origin: origin,
                parentID: rootFrame.id,
                link: geometry.link(
                    from: anchor,
                    to: rect,
                    anchor: .down,
                    depth: event.depth,
                    color: event.branch
                )
            )
            frames.append(childFrame)
            placeTail(of: event, under: rect, growth: isAbove(index) ? .up : .down, into: &frames)
            cursor += event.columnWidth + gap
        }
    }

    private func placeTail(
        of block: Block,
        under parentRect: CGRect,
        growth: Growth,
        into frames: inout [NodeFrame]
    ) {
        guard !block.children.isEmpty else { return }
        let gap = geometry.metrics.horizontalGap
        let siblingGap = geometry.metrics.siblingGap
        var cursor = growth == .up ? parentRect.minY - gap : parentRect.maxY + gap
        for child in block.children {
            let originY = growth == .up ? cursor - child.size.height : cursor
            let origin = CGPoint(x: parentRect.midX - child.size.width / 2, y: originY)
            let rect = CGRect(origin: origin, size: child.size)
            // A branch that grows up leaves from the parent's top edge; the
            // curve still uses the shared downward anchor, pinned to that edge.
            let start = growth == .up
                ? CGRect(x: parentRect.midX, y: parentRect.minY, width: 0, height: 0)
                : parentRect
            let childFrame = frame(
                for: child,
                origin: origin,
                parentID: block.node.id,
                link: geometry.link(
                    from: start,
                    to: rect,
                    anchor: .down,
                    depth: child.depth,
                    color: child.branch
                )
            )
            frames.append(childFrame)
            placeTail(of: child, under: rect, growth: growth, into: &frames)
            cursor = growth == .up
                ? rect.minY - child.tailHeight - siblingGap
                : rect.maxY + child.tailHeight + siblingGap
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
        var columnWidth = size.width
        for child in children {
            columnWidth = max(columnWidth, child.columnWidth)
        }
        var tailHeight: CGFloat = 0
        if !children.isEmpty {
            let stack = children.reduce(CGFloat(0)) { $0 + $1.fullHeight }
                + geometry.metrics.siblingGap * CGFloat(children.count - 1)
            tailHeight = geometry.metrics.horizontalGap + stack
        }
        return Block(
            node: node,
            size: size,
            children: children,
            columnWidth: columnWidth,
            tailHeight: tailHeight,
            depth: depth,
            branch: branch
        )
    }
}
