import CoreGraphics
import Foundation
import FlorettaCore
import SwiftFlow

/// Pan, zoom, and fit on top of SwiftFlow's `Viewport`.
///
/// Screen ↔ flow conversion goes through `SwiftFlowInstance`. Pointer zoom calls
/// `SwiftFlowInstance.zoomTo`, which uses SwiftFlow's own zoom math. That method
/// anchors the center of `viewSize`, so the view size is set to place the pointer
/// at that center. Fit calls `getViewportForBounds`. The 1.25 fit cap is ours:
/// one small topic should not fill the window. Interactive zoom snaps to
/// `ZoomStop` (50%…400%). 100% is scale 1, with no extra coefficient.
struct CanvasViewport: Equatable, Sendable {
    var flow: Viewport = .identity

    /// Eight-stop floor. The canvas cannot zoom out past 50%.
    static let minimumScale: CGFloat = ZoomStop.fifty.scale
    static let maximumScale: CGFloat = ZoomStop.fourHundred.scale
    /// Kept for fit. SwiftFlow's own fit default is higher.
    static let maximumFitScale: CGFloat = 1.25

    static func clampScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return ZoomStop.oneHundred.scale }
        let clamped = min(max(scale, minimumScale), maximumScale)
        let percent = (clamped * 100).rounded()
        return percent == 100 ? 1 : percent / 100
    }

    var offset: CGPoint {
        get { CGPoint(x: flow.x, y: flow.y) }
        set {
            flow.x = newValue.x
            flow.y = newValue.y
        }
    }

    var scale: CGFloat { flow.zoom }

    var persisted: CanvasViewportState {
        CanvasViewportState(scale: Double(scale), offsetX: Double(offset.x), offsetY: Double(offset.y))
    }

    mutating func restore(_ state: CanvasViewportState) {
        let state = CanvasViewportState.clamped(state)
        flow = Viewport(x: CGFloat(state.offsetX), y: CGFloat(state.offsetY), zoom: CGFloat(state.scale))
    }

    /// Visible canvas rectangle for a view of `viewSize`.
    /// Inverse of SwiftFlow's `screen = flow * zoom + offset`.
    func canvasRect(in viewSize: CGSize) -> CGRect {
        let zoom = max(scale, Viewport.minZoom)
        let minX = (0 - offset.x) / zoom
        let minY = (0 - offset.y) / zoom
        let maxX = (viewSize.width - offset.x) / zoom
        let maxY = (viewSize.height - offset.y) / zoom
        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    @MainActor
    func canvasPoint(fromView point: CGPoint) -> CGPoint {
        bridge.screenToFlowPosition(point)
    }

    @MainActor
    func viewPoint(fromCanvas point: CGPoint) -> CGPoint {
        bridge.flowToScreenPosition(point)
    }

    @MainActor
    func viewRect(fromCanvas rect: CGRect) -> CGRect {
        let origin = viewPoint(fromCanvas: rect.origin)
        let far = viewPoint(fromCanvas: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
    }

    mutating func pan(by delta: CGSize) {
        flow.x += delta.width
        flow.y += delta.height
    }

    @MainActor
    mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        zoom(to: scale * factor, around: viewPoint)
    }

    @MainActor
    mutating func zoom(to newScale: CGFloat, around anchor: CGPoint) {
        let clamped = Self.clampScale(newScale)
        let instance = bridge
        instance.viewSize = CGSize(width: anchor.x * 2, height: anchor.y * 2)
        instance.zoomTo(clamped, animated: false)
        flow = instance.viewport
        if !flow.zoom.isFinite || flow.zoom < Self.minimumScale || flow.zoom > Self.maximumScale {
            flow.zoom = clamped
        }
    }

    /// Scroll-wheel / trackpad. Command zooms around the pointer; otherwise pans.
    @MainActor
    mutating func applyScroll(delta: CGSize, around viewPoint: CGPoint, command: Bool) {
        if command {
            let factor = CGFloat(exp(Double(delta.height) * 0.002))
            zoom(by: factor, around: viewPoint)
            snapToStop(around: viewPoint)
        } else {
            pan(by: delta)
        }
    }

    /// Gesture end. The scale becomes exactly one `ZoomStop`.
    @MainActor
    mutating func snapToStop(around anchor: CGPoint) {
        let integerPercent = CGFloat((scale * 100).rounded()) / 100
        guard integerPercent != scale else { return }
        zoom(to: integerPercent, around: anchor)
    }

    mutating func fit(content: CGRect, in viewSize: CGSize, padding: CGFloat = 48) {
        guard content.width > 1, content.height > 1,
              viewSize.width > padding * 2, viewSize.height > padding * 2 else {
            flow = Viewport(x: viewSize.width / 2, y: viewSize.height / 2, zoom: 1)
            return
        }
        flow = getViewportForBounds(
            bounds: content,
            viewportSize: viewSize,
            minZoom: Self.minimumScale,
            maxZoom: Self.maximumFitScale,
            padding: padding
        )
        let oldScale = flow.zoom
        let roundedScale = Self.clampScale(oldScale)
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let canvasCenter = CGPoint(x: (center.x - flow.x) / oldScale, y: (center.y - flow.y) / oldScale)
        flow.zoom = roundedScale
        flow.x = center.x - canvasCenter.x * roundedScale
        flow.y = center.y - canvasCenter.y * roundedScale
    }

    @MainActor
    private var bridge: SwiftFlowInstance {
        let instance = SwiftFlowInstance()
        instance.viewport = flow
        return instance
    }
}
