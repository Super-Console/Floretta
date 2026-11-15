import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The shipped mind map: root centered, children split into a left and a right side
/// by subtree height. Manual root points and free nodes keep their stored origin.
struct BilateralLayout: StructureLayout {
    let geometry: LayoutGeometry

    var kind: LayoutKind { .bilateral }

    private struct Measured {
        var node: MindMapNode
        var size: CGSize
        var children: [Measured]
        var blockHeight: CGFloat
        var depth: Int
        var branch: BranchColor
    }

    func place(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        for root in document.roots {
            geometry.collectHeights(root, depth: 0, into: &levelHeights)
        }
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        var placedAutoRoot = false
        for root in document.roots {
            if root.position != nil {
                appendManual(
                    root,
                    depth: 0,
                    parentID: nil,
                    isRoot: true,
                    parentRect: nil,
                    branch: .black,
                    heights: levelHeights,
                    into: &frames
                )
                continue
            }
            let autos = root.isCollapsed ? [] : root.children.filter { $0.position == nil }
            let sides = split(autos, parent: root, depth: 1, heights: levelHeights)
            let rootSize = geometry.size(root, depth: 0, heights: levelHeights)
            let blockHeight = max(rootSize.height, stackHeight(sides.right), stackHeight(sides.left))
            let centerY = placedAutoRoot ? nextTop + blockHeight / 2 : 0
            let origin = CGPoint(x: -rootSize.width / 2, y: centerY - rootSize.height / 2)
            let rootFrame = geometry.frame(
                node: root,
                origin: origin,
                size: rootSize,
                depth: 0,
                isRoot: true,
                parentID: nil,
                branch: .black,
                link: nil
            )
            frames.append(rootFrame)
            place(sides.right, side: .right, parent: rootFrame, centerY: centerY, heights: levelHeights, into: &frames)
            place(sides.left, side: .left, parent: rootFrame, centerY: centerY, heights: levelHeights, into: &frames)
            if !root.isCollapsed {
                for child in root.children where child.position != nil {
                    let color = geometry.appearance.palette.color(at: geometry.childIndex(of: child, in: root))
                    appendManual(
                        child,
                        depth: 1,
                        parentID: root.id,
                        isRoot: false,
                        parentRect: rootFrame.rect,
                        branch: color,
                        heights: levelHeights,
                        into: &frames
                    )
                }
            }
            nextTop = centerY + blockHeight / 2 + geometry.metrics.siblingGap * 2
            placedAutoRoot = true
        }
        // Free nodes are not measured into `levelHeights` and are not passed to `split`.
        // Their origin is the stored point, including while that point is being dragged.
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    private func split(
        _ children: [MindMapNode],
        parent: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat]
    ) -> (left: [Measured], right: [Measured]) {
        var left: [Measured] = []
        var right: [Measured] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        for child in children {
            let color = geometry.appearance.palette.color(at: geometry.childIndex(of: child, in: parent))
            let block = measure(child, depth: depth, branch: color, heights: heights)
            let rightNext = right.isEmpty
                ? block.blockHeight
                : rightHeight + geometry.metrics.siblingGap + block.blockHeight
            let leftNext = left.isEmpty
                ? block.blockHeight
                : leftHeight + geometry.metrics.siblingGap + block.blockHeight
            // A topic that names its side goes there: `side` is written by the
            // left/right add handle, and an imported FreeMind `POSITION` means the
            // same thing. Everything else keeps the height-balancing rule, so a map
            // with no stored sides lays out exactly as it did before.
            let growsRight: Bool
            switch child.side {
            case .right:
                growsRight = true
            case .left:
                growsRight = false
            case nil:
                growsRight = rightNext < leftNext || (rightNext == leftNext && right.count <= left.count)
            }
            if growsRight {
                right.append(block)
                rightHeight = rightNext
            } else {
                left.append(block)
                leftHeight = leftNext
            }
        }
        return (left, right)
    }

    private func measure(
        _ node: MindMapNode,
        depth: Int,
        branch: BranchColor,
        heights: [Int: CGFloat]
    ) -> Measured {
        let size = geometry.size(
            node,
            depth: depth,
            heights: heights,
            reservesChildBadge: depth > 0 && geometry.appearance.childCountBadgeInset > 0
        )
        let kids = node.isCollapsed ? [] : node.children.filter { $0.position == nil }
        let children = kids.map { measure($0, depth: depth + 1, branch: branch, heights: heights) }
        return Measured(
            node: node,
            size: size,
            children: children,
            blockHeight: stacked(children, minimum: size.height),
            depth: depth,
            branch: branch
        )
    }

    private func stackHeight(_ blocks: [Measured]) -> CGFloat {
        stacked(blocks, minimum: 0)
    }

    private func stacked(_ blocks: [Measured], minimum: CGFloat) -> CGFloat {
        guard !blocks.isEmpty else { return minimum }
        let gaps = geometry.metrics.siblingGap * CGFloat(blocks.count - 1)
        return max(minimum, blocks.reduce(CGFloat(0)) { $0 + $1.blockHeight } + gaps)
    }

    private func place(
        _ blocks: [Measured],
        side: LinkAnchor,
        parent: NodeFrame,
        centerY: CGFloat,
        heights: [Int: CGFloat],
        into frames: inout [NodeFrame]
    ) {
        let height = stackHeight(blocks)
        var top = centerY - height / 2
        for block in blocks {
            let y = top + (block.blockHeight - block.size.height) / 2
            let x = side == .right
                ? parent.rect.maxX + geometry.metrics.horizontalGap
                : parent.rect.minX - geometry.metrics.horizontalGap - block.size.width
            let origin = CGPoint(x: x, y: y)
            let rect = CGRect(origin: origin, size: block.size)
            let frame = geometry.frame(
                node: block.node,
                origin: origin,
                size: block.size,
                depth: block.depth,
                isRoot: false,
                parentID: parent.id,
                branch: block.branch,
                link: geometry.link(
                    from: parent.rect,
                    to: rect,
                    anchor: side,
                    depth: block.depth,
                    color: block.branch
                ),
                childBadgeInset: geometry.appearance.childCountBadgeInset,
                childBadgeOnMinX: side == .left
            )
            frames.append(frame)
            place(block.children, side: side, parent: frame, centerY: rect.midY, heights: heights, into: &frames)
            if !block.node.isCollapsed {
                for child in block.node.children where child.position != nil {
                    appendManual(
                        child,
                        depth: block.depth + 1,
                        parentID: block.node.id,
                        isRoot: false,
                        parentRect: rect,
                        branch: block.branch,
                        heights: heights,
                        into: &frames
                    )
                }
            }
            top += block.blockHeight + geometry.metrics.siblingGap
        }
    }

    private func appendManual(
        _ node: MindMapNode,
        depth: Int,
        parentID: UUID?,
        isRoot: Bool,
        parentRect: CGRect?,
        branch: BranchColor,
        heights: [Int: CGFloat],
        into frames: inout [NodeFrame]
    ) {
        guard let position = node.position else { return }
        let reserveBadge = !isRoot && geometry.appearance.childCountBadgeInset > 0
        let size = geometry.size(node, depth: depth, heights: heights, reservesChildBadge: reserveBadge)
        let origin = CGPoint(x: position.x, y: position.y)
        let rect = CGRect(origin: origin, size: size)
        let anchor: LinkAnchor = rect.midX >= (parentRect?.midX ?? rect.midX) ? .right : .left
        let link = parentRect.map {
            geometry.link(from: $0, to: rect, anchor: anchor, depth: depth, color: branch)
        }
        frames.append(
            geometry.frame(
                node: node,
                origin: origin,
                size: size,
                depth: depth,
                isRoot: isRoot,
                parentID: parentID,
                branch: branch,
                link: link,
                childBadgeInset: reserveBadge ? geometry.appearance.childCountBadgeInset : 0,
                childBadgeOnMinX: anchor == .left
            )
        )
    }
}
