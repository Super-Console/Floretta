import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Trackpad and mouse-wheel input. Clicks pass through to the SwiftUI drag gesture.
struct CanvasScrollCatcher: View {
    var onScroll: (CGSize, CGPoint, Bool) -> Void

    var body: some View {
        #if os(macOS)
        MacScrollCatcher(onScroll: onScroll)
        #else
        IOSScrollCatcher(onScroll: onScroll)
        #endif
    }
}

#if os(macOS)
private struct MacScrollCatcher: NSViewRepresentable {
    var onScroll: (CGSize, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollWheelView, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollWheelView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.stop()
        }
    }
}

private final class ScrollWheelView: NSView, @unchecked Sendable {
    var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
    /// Register and remove only from the main actor. deinit must not touch this.
    @MainActor private var monitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            MainActor.assumeIsolated {
                stop()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let attached = window != nil
        MainActor.assumeIsolated {
            stop()
            guard attached else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window == window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                // A monitor is window-wide, and this overlay covers the whole
                // canvas frame, so the pointer over the inspector column or the
                // outline panel is still inside `bounds`. The window's hit test
                // is what knows the difference: if the pointer is on a scroll
                // view that floats above the canvas, that view owns the gesture
                // and the event has to reach it.
                guard CanvasScrollScope.shouldConsume(
                    hitChain: self.scrollHitChain(for: event),
                    pointInCanvas: self.bounds.contains(local)
                ) else { return event }
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
                let delta = CGSize(
                    width: event.scrollingDeltaX * multiplier,
                    height: event.scrollingDeltaY * multiplier
                )
                self.onScroll?(delta, local, event.modifierFlags.contains(.command))
                return nil
            }
        }
    }

    /// What the window's hit test found under the pointer, deepest view first.
    ///
    /// Only the views between the pointer and the canvas's own container are
    /// reported. The walk stops at the first ancestor that also contains this
    /// overlay: anything above that common ancestor is window scaffolding, not
    /// a panel floating over the canvas, so its scroll views are not what the
    /// pointer is on.
    private func scrollHitChain(for event: NSEvent) -> [CanvasScrollHit] {
        guard let root = window?.contentView, let hit = root.hitTest(event.locationInWindow) else {
            // Nothing under the pointer: transparent canvas pixels.
            return [.canvas]
        }
        var chain: [CanvasScrollHit] = []
        var view: NSView? = hit
        while let current = view {
            if current === self || self.isDescendant(of: current) { break }
            if current is NSScrollView {
                chain.append(.scrollView)
            } else if chain.isEmpty {
                chain.append(.other)
            }
            view = current.superview
        }
        // Only canvas pixels and its own non-scrolling overlays between the
        // pointer and the canvas's container.
        return chain.isEmpty ? [.canvas] : chain
    }

    /// Drops the local monitor. Safe to call more than once.
    @MainActor
    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
#else
private struct IOSScrollCatcher: UIViewRepresentable {
    var onScroll: (CGSize, CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateUIView(_ view: ScrollWheelView, context: Context) {
        view.onScroll = onScroll
    }
}

private final class ScrollWheelView: UIView, @unchecked Sendable {
    var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
    private var pan: UIPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, pan == nil else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        pan.allowedScrollTypesMask = .all
        pan.cancelsTouchesInView = false
        window.addGestureRecognizer(pan)
        self.pan = pan
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil, let pan {
            pan.view?.removeGestureRecognizer(pan)
            self.pan = nil
        }
        super.willMove(toWindow: newWindow)
    }

    @objc private func scrolled(_ pan: UIPanGestureRecognizer) {
        guard pan.numberOfTouches == 0 else { return }
        guard let window else { return }
        let local = convert(pan.location(in: window), from: window)
        guard bounds.contains(local) else { return }
        let translation = pan.translation(in: window)
        pan.setTranslation(.zero, in: window)
        let delta = CGSize(width: translation.x, height: translation.y)
        onScroll?(delta, local, pan.modifierFlags.contains(.command))
    }
}
#endif
