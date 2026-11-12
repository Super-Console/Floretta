import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One row of the zoom menu. Stops are the existing `ZoomStop` scale.
/// Fit has no fixed scale; the canvas fits, then snaps to a stop.
public enum EditorStatusZoomChoice: Hashable, Sendable {
    case stop(ZoomStop)
    case fitWindow

    public static var menu: [EditorStatusZoomChoice] {
        ZoomStop.allCases.map { .stop($0) } + [.fitWindow]
    }

    /// Scale passed to the existing viewport. Nil for fit.
    public var fixedScale: CGFloat? {
        switch self {
        case .stop(let stop):
            return stop.scale
        case .fitWindow:
            return nil
        }
    }

    /// Menu title. Percent stops match `ZoomStop`. Fit uses the existing command name.
    public var menuTitle: String {
        switch self {
        case .stop(let stop):
            return "\(stop.percent)%"
        case .fitWindow:
            return "适应窗口"
        }
    }
}

/// Soft fade around the borderless status strip. 8–16pt, no plate or shadow.
public enum EditorStatusBarChrome: Sendable {
    public static let featherInset: CGFloat = 12
    public static let controlMinHeight: CGFloat = 44
}

/// Controls on the one bottom bar, leading to trailing.
/// Topic counts live in the overflow menu via `TopicTitleCensus`. This list does not count text.
public enum EditorStatusControl: String, Equatable, Sendable {
    case zoomMenu
    case viewSwitcher
}

/// How many standalone toolbar buttons fit. Compact widths keep only
/// `insert` and the trailing overflow so iOS does not mint a second ellipsis.
public enum EditorToolbarWidthClass: Equatable, Sendable {
    case compact
    case regular
}

public enum EditorToolbarLayout {
    /// Standalone toolbar buttons for the current width. `more` is always last
    /// and is the only command whose symbol is `ellipsis`.
    public static func visibleItems(for width: EditorToolbarWidthClass) -> [EditorToolbarCommandID] {
        switch width {
        case .compact:
            return [.insert, .more]
        case .regular:
            return EditorToolbarCatalog.defaultToolbarItems
        }
    }
}

public enum EditorStatusBarModel {
    public static let controls: [EditorStatusControl] = [
        .zoomMenu,
        .viewSwitcher,
    ]

    /// Writes a menu stop into the chrome percent the editor already displays.
    /// `CanvasCamera.zoom(to:)` does this after it changes the viewport scale.
    /// Fit is left untouched: the camera fits the content, then syncs.
    public static func apply(_ choice: EditorStatusZoomChoice, to chrome: inout CanvasChrome) {
        guard let scale = choice.fixedScale else { return }
        chrome.syncZoomPercent(toScale: scale)
    }
}
