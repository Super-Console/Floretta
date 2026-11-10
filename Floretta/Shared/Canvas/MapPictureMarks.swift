import CoreGraphics
import FlorettaCore
import SwiftUI

enum TopicTagCanvas {
    static let highlight = BranchColor(red: 196.0 / 255, green: 92.0 / 255, blue: 38.0 / 255)
    static let dimOpacity = 0.28

    static func draw(
        node: NodeFrame,
        in rect: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color,
        ink: Color
    ) {
        guard node.tagBandHeight > 0, node.size.height > 1, rect.width > 8, rect.height > 8 else { return }
        let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: node.fileBadges.count))
        let scaleY = rect.height / node.size.height
        let scaleX = rect.width / max(node.size.width, 1)
        let tagHeight = node.tagBandHeight * scaleY
        let fileHeight = fileBand * scaleY
        let inset = 6 * min(scaleX, 1.4)
        var cursor = CGRect(
            x: rect.minX + inset,
            y: rect.maxY - fileHeight - tagHeight,
            width: max(0, rect.width - inset * 2),
            height: tagHeight
        )
        let gap = CGFloat(TopicTagLayout.gap) * scaleY
        cursor.origin.y += gap
        cursor.size.height = max(0, cursor.height - gap)
        let row = CGFloat(TopicTagLayout.rowHeight) * scaleY
        guard cursor.width > 1, row > 1 else { return }
        if !node.markerIDs.isEmpty {
            drawMarkers(
                node.markerIDs,
                in: CGRect(x: cursor.minX, y: cursor.minY, width: cursor.width, height: row),
                context: context,
                color: color
            )
            cursor.origin.y += row
            cursor.size.height = max(0, cursor.height - row)
        }
        guard !node.labels.isEmpty, cursor.height > 1 else { return }
        let box = CGRect(x: cursor.minX, y: cursor.minY, width: cursor.width, height: min(row, cursor.height))
        var layer = context
        layer.clip(to: Path(box))
        let point = max(8, min(13, box.height * 0.8))
        layer.draw(
            Text(node.labels.joined(separator: "  "))
                .font(.system(size: point))
                .foregroundStyle(ink),
            at: CGPoint(x: box.minX, y: box.midY),
            anchor: .leading
        )
    }

    private static func drawMarkers(
        _ markerIDs: [String],
        in row: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color
    ) {
        let side = min(row.height - 1, 14)
        guard side > 3 else { return }
        var x = row.minX
        for markerId in markerIDs {
            if x + side > row.maxX { break }
            let mark = CGRect(x: x, y: row.midY - side / 2, width: side, height: side)
            drawMarker(markerId, in: mark, context: context, color: color)
            x += side + 3
        }
    }

    private static func drawMarker(
        _ markerId: String,
        in mark: CGRect,
        context: GraphicsContext,
        color: (BranchColor) -> Color
    ) {
        if let fraction = TopicMarkerCatalog.progressFraction(markerId) {
            let track = BranchColor(red: 0.62, green: 0.64, blue: 0.66)
            let fill = BranchColor(red: 0.18, green: 0.62, blue: 0.32)
            context.stroke(Path(ellipseIn: mark), with: .color(color(track)), lineWidth: 1)
            if fraction >= 1 {
                context.fill(Path(ellipseIn: mark.insetBy(dx: 1, dy: 1)), with: .color(color(fill)))
            } else if fraction > 0 {
                context.fill(pie(in: mark.insetBy(dx: 1, dy: 1), fraction: fraction), with: .color(color(fill)))
            }
            return
        }
        if TopicMarkerCatalog.group(of: markerId) == .flag, let flag = TopicMarkerCatalog.color(for: markerId) {
            var cloth = Path()
            cloth.move(to: CGPoint(x: mark.minX + 1, y: mark.minY))
            cloth.addLine(to: CGPoint(x: mark.maxX, y: mark.midY))
            cloth.addLine(to: CGPoint(x: mark.minX + 1, y: mark.maxY))
            cloth.closeSubpath()
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: mark.minX + 1, y: mark.minY))
                    path.addLine(to: CGPoint(x: mark.minX + 1, y: mark.maxY))
                },
                with: .color(color(flag)),
                lineWidth: 1.25
            )
            context.fill(cloth, with: .color(color(flag)))
            return
        }
        let ink = TopicMarkerCatalog.color(for: markerId) ?? BranchColor(red: 0.45, green: 0.47, blue: 0.50)
        context.fill(Path(ellipseIn: mark), with: .color(color(ink)))
        if let number = TopicMarkerCatalog.priorityNumber(markerId), mark.height >= 8 {
            context.draw(
                Text("\(number)")
                    .font(.system(size: max(7, mark.height * 0.62)))
                    .foregroundStyle(Color.white),
                at: CGPoint(x: mark.midX, y: mark.midY),
                anchor: .center
            )
        }
    }

    private static func pie(in rect: CGRect, fraction: Double) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

enum ImagePlacement {
    static func rect(for image: CGImage, in node: CGRect) -> CGRect {
        let slot = ImageSlot.slot(nodeWidth: Double(node.width))
        let fitted = ImageAspectFit.fit(
            pixels: ImagePixelSize(width: image.width, height: image.height),
            in: slot
        )
        return CGRect(
            x: node.minX + CGFloat(fitted.x),
            y: node.minY + CGFloat(fitted.y),
            width: CGFloat(fitted.width),
            height: CGFloat(fitted.height)
        )
    }
}
