import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 树型表格: one column per depth, rows are subtrees.
///
/// The topic column is the first column, and the indentation of a level is the
/// column it lands in: column `d` starts one `horizontalGap` past the widest
/// topic of column `d - 1`, so every topic of a level shares one left edge and
/// the whole map reads as a table. A row's height is the taller of the topic and
/// the stack of its children — a wrapped title grows its own row, and the row is
/// never smaller than what `LayoutGeometry` measured. A topic is vertically
/// centred on its own row, and rows are `siblingGap` apart.
public struct TreeTableLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .treeTable }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    private struct Block {
        var node: MindMapNode
        var size: CGSize
        var children: [Block]
        /// Height of this topic and every row under it, gaps included.
        var bandHeight: CGFloat
        var depth: Int
        var branch: BranchColor
    }

    public func place(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        var columnWidths: [Int: CGFloat] = [:]
        for root in document.roots {
            geometry.collectHeights(root, depth: 0, into: &levelHeights)
        }
        for root in document.roots {
            collectColumnWidths(root, depth: 0, heights: levelHeights, into: &columnWidths)
        }
        let columnX = columnOrigins(columnWidths)
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        for root in document.roots {
            let block = measure(root, depth: 0, branch: .black, heights: levelHeights)
            // A dragged root moves the whole table with it, so the columns stay
            // aligned to the point the user dropped.
            let xOffset = CGFloat(root.position?.x ?? 0)
            let top = CGFloat(root.position?.y ?? Double(nextTop))
            let columns = columnX.mapValues { $0 + xOffset }
            let origin = CGPoint(
                x: columns[0] ?? xOffset,
                y: top + (block.bandHeight - block.size.height) / 2
            )
            let rootFrame = frame(for: block, origin: origin, parentID: nil, link: nil)
            frames.append(rootFrame)
            placeChildren(of: block, parentRect: rootFrame.frame, bandTop: top, columnX: columns, into: &frames)
            nextTop = top + block.bandHeight + geometry.metrics.siblingGap * 2
        }
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    /// Left edge of every column. Column 0 is the topic column.
    private func columnOrigins(_ widths: [Int: CGFloat]) -> [Int: CGFloat] {
        guard let deepest = widths.keys.max() else { return [0: 0] }
        var origins: [Int: CGFloat] = [0: 0]
        var x: CGFloat = 0
        for depth in 0...deepest {
            origins[depth] = x
            x += (widths[depth] ?? 0) + geometry.metrics.horizontalGap
        }
        return origins
    }

    private func collectColumnWidths(
        _ node: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat],
        into widths: inout [Int: CGFloat]
    ) {
        let size = geometry.size(node, depth: depth, heights: heights)
        widths[depth] = max(widths[depth] ?? 0, size.width)
        guard !node.isCollapsed else { return }
        // A manually placed topic keeps its own point and is not part of this
        // table, which matches how `measure` filters it out.
        for child in node.children where child.position == nil {
            collectColumnWidths(child, depth: depth + 1, heights: heights, into: &widths)
        }
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
            childBadgeOnMinX: false
        )
    }

    private func placeChildren(
        of block: Block,
        parentRect: CGRect,
        bandTop: CGFloat,
        columnX: [Int: CGFloat],
        into frames: inout [NodeFrame]
    ) {
        guard !block.children.isEmpty else { return }
        var cursor = bandTop
        for child in block.children {
            let origin = CGPoint(
                x: columnX[child.depth] ?? 0,
                y: cursor + (child.bandHeight - child.size.height) / 2
            )
            let rect = CGRect(origin: origin, size: child.size)
            let childFrame = frame(
                for: child,
                origin: origin,
                parentID: block.node.id,
                link: geometry.link(
                    from: parentRect,
                    to: rect,
                    anchor: .right,
                    depth: child.depth,
                    color: child.branch
                )
            )
            frames.append(childFrame)
            placeChildren(of: child, parentRect: rect, bandTop: cursor, columnX: columnX, into: &frames)
            cursor += child.bandHeight + geometry.metrics.siblingGap
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
        var bandHeight = size.height
        if !children.isEmpty {
            let stack = children.reduce(CGFloat(0)) { $0 + $1.bandHeight }
                + geometry.metrics.siblingGap * CGFloat(children.count - 1)
            bandHeight = max(bandHeight, stack)
        }
        return Block(
            node: node,
            size: size,
            children: children,
            bandHeight: bandHeight,
            depth: depth,
            branch: branch
        )
    }
}
