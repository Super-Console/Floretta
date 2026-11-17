import CoreGraphics
import Foundation

/// The two viewport queries needed to paint the canvas, collected in one pass.
/// Node frames and their links are tested independently: a curve can cross the
/// viewport even when its owning node is entirely outside it.
public struct CanvasViewportDrawSelection: Equatable, Sendable {
    public let visibleNodes: [NodeFrame]
    public let visibleLinkNodeIDs: Set<UUID>

    public init(visibleNodes: [NodeFrame], visibleLinkNodeIDs: Set<UUID>) {
        self.visibleNodes = visibleNodes
        self.visibleLinkNodeIDs = visibleLinkNodeIDs
    }

    public static func select(frames: [NodeFrame], in viewport: CGRect) -> Self {
        guard viewport.width > 0, viewport.height > 0,
              viewport.minX.isFinite, viewport.minY.isFinite,
              viewport.maxX.isFinite, viewport.maxY.isFinite else {
            return Self(visibleNodes: [], visibleLinkNodeIDs: [])
        }

        var visibleNodes: [NodeFrame] = []
        var visibleLinks = Set<UUID>()
        visibleNodes.reserveCapacity(frames.count)
        visibleLinks.reserveCapacity(frames.count)

        for frame in frames {
            if frame.frame.intersects(viewport) {
                visibleNodes.append(frame)
            }
            if let link = frame.link, curveBounds(link).intersects(viewport) {
                visibleLinks.insert(frame.id)
            }
        }

        return Self(visibleNodes: visibleNodes, visibleLinkNodeIDs: visibleLinks)
    }

    /// A cubic Bézier stays inside the convex hull of its control points, so
    /// this inexpensive box may include false positives but cannot cull a
    /// visible branch curve.
    public static func curveBounds(_ link: LinkCurve) -> CGRect {
        let minX = min(min(link.start.x, link.control1.x), min(link.control2.x, link.end.x))
        let minY = min(min(link.start.y, link.control1.y), min(link.control2.y, link.end.y))
        let maxX = max(max(link.start.x, link.control1.x), max(link.control2.x, link.end.x))
        let maxY = max(max(link.start.y, link.control1.y), max(link.control2.y, link.end.y))
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0.01),
            height: max(maxY - minY, 0.01)
        )
    }
}
