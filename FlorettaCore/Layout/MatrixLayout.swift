import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// XMind 矩阵图: a two-dimensional grid of columns and rows.
///
/// First-level topics are the column headers: each one owns one grid column, and
/// a column is as wide as its widest topic so the whole column shares one left
/// edge. Second-level topics are the rows: row `k` is the k-th child of each
/// column, and a row is as tall as the tallest cell in it, so column `j`'s row
/// `k` and column `j + 1`'s row `k` sit on the same y. A leaf of a second-level
/// topic lands in the crossing cell of its column and its row, stacked under its
/// parent inside that cell. Cells are disjoint rectangles, so no two topics can
/// overlap, and both axes stay aligned because every x comes from a column origin
/// and every y from a row origin.
public struct MatrixLayout: StructureLayout {
    public let geometry: LayoutGeometry

    public var kind: LayoutKind { .matrix }

    public init(geometry: LayoutGeometry) {
        self.geometry = geometry
    }

    /// A second-level topic and everything stacked under it inside one cell.
    private struct Cell {
        var node: MindMapNode
        var size: CGSize
        var children: [Cell]
        /// The cell's own topic plus every descendant, gaps included.
        var stackHeight: CGFloat
        var depth: Int
        var branch: BranchColor
    }

    /// A first-level topic: one column header, one column of the grid.
    private struct Column {
        var node: MindMapNode
        var size: CGSize
        var cells: [Cell]
        var width: CGFloat
        var branch: BranchColor
    }

    public func place(_ document: MindMapDocument) -> [NodeFrame] {
        var levelHeights: [Int: CGFloat] = [:]
        for root in document.roots {
            geometry.collectHeights(root, depth: 0, into: &levelHeights)
        }
        var frames: [NodeFrame] = []
        var nextTop: CGFloat = 0
        for root in document.roots {
            let rootSize = geometry.size(root, depth: 0, heights: levelHeights)
            let columns = self.columns(of: root, heights: levelHeights)
            let origin: CGPoint
            if let position = root.position {
                origin = CGPoint(x: position.x, y: position.y)
            } else {
                origin = CGPoint(x: 0, y: nextTop)
            }
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

            let gap = geometry.metrics.horizontalGap
            let headerTop = rootFrame.frame.maxY + gap
            var columnX: [CGFloat] = []
            var cursor: CGFloat = 0
            for column in columns {
                columnX.append(cursor)
                cursor += column.width + gap
            }
            let rowCount = columns.map(\.cells.count).max() ?? 0
            var rowBands = [CGFloat](repeating: 0, count: rowCount)
            for column in columns {
                for (index, cell) in column.cells.enumerated() {
                    rowBands[index] = max(rowBands[index], cell.stackHeight)
                }
            }
            var rowTop: [CGFloat] = []
            if rowCount > 0 {
                var y = headerTop + (columns.map(\.size.height).max() ?? 0) + gap
                for band in rowBands {
                    rowTop.append(y)
                    y += band + geometry.metrics.siblingGap
                }
            }

            for (index, column) in columns.enumerated() {
                let columnOrigin = CGPoint(x: columnX[index], y: headerTop)
                let columnRect = CGRect(origin: columnOrigin, size: column.size)
                let columnFrame = geometry.frame(
                    node: column.node,
                    origin: columnOrigin,
                    size: column.size,
                    depth: 1,
                    isRoot: false,
                    parentID: rootFrame.id,
                    branch: column.branch,
                    link: geometry.link(
                        from: rootFrame.frame,
                        to: columnRect,
                        anchor: .down,
                        depth: 1,
                        color: column.branch
                    ),
                    childBadgeInset: geometry.appearance.childCountBadgeInset,
                    childBadgeOnMinX: false
                )
                frames.append(columnFrame)
                for (row, cell) in column.cells.enumerated() {
                    let cellOrigin = CGPoint(x: columnX[index], y: rowTop[row])
                    place(
                        cell,
                        origin: cellOrigin,
                        parentID: columnFrame.id,
                        parentRect: columnRect,
                        into: &frames
                    )
                }
            }
            nextTop = bottom(of: frames, from: origin.y) + geometry.metrics.siblingGap * 2
        }
        for node in document.freeNodes {
            geometry.appendFree(node, into: &frames)
        }
        return frames
    }

    private func bottom(of frames: [NodeFrame], from top: CGFloat) -> CGFloat {
        frames.reduce(top) { max($0, $1.frame.maxY) }
    }

    /// A cell places its own topic, then stacks its descendants below it.
    private func place(
        _ cell: Cell,
        origin: CGPoint,
        parentID: UUID,
        parentRect: CGRect,
        into frames: inout [NodeFrame]
    ) {
        let rect = CGRect(origin: origin, size: cell.size)
        let frame = geometry.frame(
            node: cell.node,
            origin: origin,
            size: cell.size,
            depth: cell.depth,
            isRoot: false,
            parentID: parentID,
            branch: cell.branch,
            link: geometry.link(
                from: parentRect,
                to: rect,
                anchor: .down,
                depth: cell.depth,
                color: cell.branch
            ),
            childBadgeInset: geometry.appearance.childCountBadgeInset,
            childBadgeOnMinX: false
        )
        frames.append(frame)
        guard !cell.children.isEmpty else { return }
        var cursor = rect.maxY + geometry.metrics.horizontalGap
        for child in cell.children {
            place(
                child,
                origin: CGPoint(x: origin.x, y: cursor),
                parentID: frame.id,
                parentRect: rect,
                into: &frames
            )
            cursor += child.stackHeight + geometry.metrics.siblingGap
        }
    }

    private func columns(of root: MindMapNode, heights: [Int: CGFloat]) -> [Column] {
        guard !root.isCollapsed else { return [] }
        return root.children.filter { $0.position == nil }.map { child in
            let size = geometry.size(child, depth: 1, heights: heights)
            let branch = geometry.appearance.palette.color(
                at: geometry.childIndex(of: child, in: root)
            )
            let cells = self.cells(of: child, depth: 2, heights: heights)
            var width = size.width
            for cell in cells {
                width = max(width, maxWidth(of: cell))
            }
            return Column(node: child, size: size, cells: cells, width: width, branch: branch)
        }
    }

    private func maxWidth(of cell: Cell) -> CGFloat {
        cell.children.reduce(cell.size.width) { max($0, maxWidth(of: $1)) }
    }

    private func cells(
        of node: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat]
    ) -> [Cell] {
        guard !node.isCollapsed else { return [] }
        return node.children.filter { $0.position == nil }.map { child in
            let size = geometry.size(child, depth: depth, heights: heights)
            let branch = geometry.appearance.palette.color(
                at: geometry.childIndex(of: child, in: node)
            )
            let kids = cells(of: child, depth: depth + 1, heights: heights)
            return Cell(
                node: child,
                size: size,
                children: kids,
                stackHeight: stackHeight(of: size, children: kids),
                depth: depth,
                branch: branch
            )
        }
    }

    private func stackHeight(of size: CGSize, children: [Cell]) -> CGFloat {
        guard !children.isEmpty else { return size.height }
        let stack = children.reduce(CGFloat(0)) { $0 + $1.stackHeight }
            + geometry.metrics.siblingGap * CGFloat(children.count - 1)
        return size.height + geometry.metrics.horizontalGap + stack
    }
}
