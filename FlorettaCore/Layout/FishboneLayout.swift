import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 鱼骨图: a horizontal spine with diagonal ribs, alternating above and
/// below it.
///
/// Each first-level topic owns one rib. The rib leaves the spine at an attach
/// point and runs up-right (or down-right) at 45°, and the branch head plus every
/// descendant sits on that same ray in tree order. Consecutive topics on the rib
/// are one `horizontalGap` apart on x, so two AABBs on one rib can never overlap;
/// two ribs on the same side of the spine get disjoint x lanes, so ribs cannot
/// overlap each other either. Root→rib and parent→child links both leave from the
/// right edge, which is the rib direction by construction.
public struct FishboneLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .fishbone }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    private struct Block {
        var node: MindMapNode
        var size: CGSize
        var children: [Block]
        var depth: Int
        var branch: BranchColor
    }

    /// One topic placed on a rib. Offsets are measured from the attach point on
    /// the spine, positive so the same numbers work on both sides.
    private struct ChainNode {
        var node: MindMapNode
        var size: CGSize
        var depth: Int
        var branch: BranchColor
        var parentIndex: Int?
        var dx: CGFloat
        var rise: CGFloat
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
            var ribs: [(sign: CGFloat, chain: [ChainNode])] = []
            var aboveRoom: CGFloat = 0
            var belowRoom: CGFloat = 0
            for (index, bone) in block.children.enumerated() {
                var chain: [ChainNode] = []
                flatten(bone, parentIndex: nil, into: &chain)
                let sign: CGFloat = index % 2 == 0 ? -1 : 1
                if sign < 0 {
                    aboveRoom = max(aboveRoom, chain.map { $0.rise + $0.size.height / 2 }.max() ?? 0)
                } else {
                    belowRoom = max(belowRoom, chain.map { $0.rise + $0.size.height / 2 }.max() ?? 0)
                }
                ribs.append((sign, chain))
            }
            let spineY: CGFloat
            let origin: CGPoint
            if let position = root.position {
                origin = CGPoint(x: position.x, y: position.y)
                spineY = position.y + block.size.height / 2
            } else {
                spineY = nextTop + max(aboveRoom + gap, block.size.height / 2)
                origin = CGPoint(x: 0, y: spineY - block.size.height / 2)
            }
            let rootFrame = frame(for: block, origin: origin, parentID: nil, link: nil)
            frames.append(rootFrame)

            var aboveCursor = rootFrame.frame.maxX + gap
            var belowCursor = rootFrame.frame.maxX + gap
            for rib in ribs {
                let attachX = rib.sign < 0 ? aboveCursor : belowCursor
                let lane = rib.chain.reduce(CGFloat(0)) { max($0, $1.dx + $1.size.width / 2) }
                place(
                    rib.chain,
                    attachX: attachX,
                    spineY: spineY,
                    sign: rib.sign,
                    parentID: rootFrame.id,
                    into: &frames
                )
                if rib.sign < 0 {
                    aboveCursor += lane + gap
                } else {
                    belowCursor += lane + gap
                }
            }
            let bottom = frames.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
            nextTop = bottom + geometry.metrics.siblingGap * 2
        }
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    private func place(
        _ chain: [ChainNode],
        attachX: CGFloat,
        spineY: CGFloat,
        sign: CGFloat,
        parentID: UUID,
        into frames: inout [NodeFrame]
    ) {
        var rects: [CGRect] = []
        for item in chain {
            let center = CGPoint(x: attachX + item.dx, y: spineY + sign * item.rise)
            let origin = CGPoint(
                x: center.x - item.size.width / 2,
                y: center.y - item.size.height / 2
            )
            let rect = CGRect(origin: origin, size: item.size)
            // The rib head leaves the spine itself; deeper topics leave their
            // parent's right edge, which is the rib direction.
            let from = item.parentIndex.map { rects[$0] }
                ?? CGRect(x: attachX, y: spineY, width: 0, height: 0)
            let parent = item.parentIndex.map { chain[$0].node.id } ?? parentID
            let placed = frame(
                for: item,
                origin: origin,
                parentID: parent,
                link: geometry.link(
                    from: from,
                    to: rect,
                    anchor: .right,
                    depth: item.depth,
                    color: item.branch
                )
            )
            frames.append(placed)
            rects.append(rect)
        }
    }

    private func frame(
        for item: ChainNode,
        origin: CGPoint,
        parentID: UUID?,
        link: LinkCurve?
    ) -> NodeFrame {
        geometry.frame(
            node: item.node,
            origin: origin,
            size: item.size,
            depth: item.depth,
            isRoot: item.depth == 0,
            parentID: parentID,
            branch: item.branch,
            link: link,
            childBadgeInset: item.depth > 0 ? geometry.appearance.childCountBadgeInset : 0,
            childBadgeOnMinX: false
        )
    }

    private func frame(
        for block: Block,
        origin: CGPoint,
        parentID: UUID?,
        link: LinkCurve?
    ) -> NodeFrame {
        frame(
            for: ChainNode(
                node: block.node,
                size: block.size,
                depth: block.depth,
                branch: block.branch,
                parentIndex: nil,
                dx: 0,
                rise: 0
            ),
            origin: origin,
            parentID: parentID,
            link: link
        )
    }

    /// One rib in tree order: the head first, then its own rib, and so on.
    private func flatten(
        _ block: Block,
        parentIndex: Int?,
        into list: inout [ChainNode]
    ) {
        let gap = geometry.metrics.horizontalGap
        let dx: CGFloat
        if let previous = list.last {
            // Half of each box plus the gap: two consecutive boxes on the rib are
            // always `gap` apart on x, so their AABBs cannot overlap.
            dx = previous.dx + (previous.size.width + block.size.width) / 2 + gap
        } else {
            // Clears the spine on the small axis, so the head never touches it.
            dx = gap + max(block.size.width, block.size.height) / 2
        }
        let index = list.count
        list.append(
            ChainNode(
                node: block.node,
                size: block.size,
                depth: block.depth,
                branch: block.branch,
                parentIndex: parentIndex,
                dx: dx,
                rise: dx
            )
        )
        for child in block.children {
            flatten(child, parentIndex: index, into: &list)
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
        return Block(
            node: node,
            size: size,
            children: children,
            depth: depth,
            branch: branch
        )
    }
}
