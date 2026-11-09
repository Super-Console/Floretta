import CoreGraphics
import Foundation

/// Pan/zoom of an infinite canvas. View point = canvas point × scale + offset.
/// The idea matches a viewport transform (SwiftFlow-style), written for this app.
struct CanvasViewport: Equatable, Sendable {
    var offset: CGPoint = .zero
    var scale: CGFloat = 1

    static let minimumScale: CGFloat = 0.2
    static let maximumScale: CGFloat = 4
    /// Fit-all will not magnify past this, so one small node does not fill the window.
    static let maximumFitScale: CGFloat = 1.25

    func canvasPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / scale,
            y: (point.y - offset.y) / scale
        )
    }

    func viewPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.x,
            y: point.y * scale + offset.y
        )
    }

    func viewRect(fromCanvas rect: CGRect) -> CGRect {
        let origin = viewPoint(fromCanvas: rect.origin)
        return CGRect(
            origin: origin,
            size: CGSize(width: rect.width * scale, height: rect.height * scale)
        )
    }

    mutating func pan(by delta: CGSize) {
        offset.x += delta.width
        offset.y += delta.height
    }

    mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        zoom(to: scale * factor, around: viewPoint)
    }

    mutating func zoom(to newScale: CGFloat, around viewPoint: CGPoint) {
        let clamped = min(max(newScale, Self.minimumScale), Self.maximumScale)
        let canvas = canvasPoint(fromView: viewPoint)
        scale = clamped
        offset = CGPoint(
            x: viewPoint.x - canvas.x * clamped,
            y: viewPoint.y - canvas.y * clamped
        )
    }

    /// Scroll-wheel / trackpad. Command zooms around the pointer; otherwise pans.
    mutating func applyScroll(delta: CGSize, around viewPoint: CGPoint, command: Bool) {
        if command {
            let factor = CGFloat(exp(Double(delta.height) * 0.002))
            zoom(by: factor, around: viewPoint)
        } else {
            pan(by: delta)
        }
    }

    mutating func fit(content: CGRect, in viewSize: CGSize, padding: CGFloat = 48) {
        guard content.width > 1, content.height > 1,
              viewSize.width > padding * 2, viewSize.height > padding * 2 else {
            scale = 1
            offset = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            return
        }
        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2
        let fitted = min(availableWidth / content.width, availableHeight / content.height)
        scale = min(max(fitted, Self.minimumScale), Self.maximumFitScale)
        let drawn = CGSize(width: content.width * scale, height: content.height * scale)
        offset = CGPoint(
            x: (viewSize.width - drawn.width) / 2 - content.minX * scale,
            y: (viewSize.height - drawn.height) / 2 - content.minY * scale
        )
    }
}
