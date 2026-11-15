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

/// The one set of numbers both bottom capsules draw from: the canvas sheet
/// capsule (TD-002) on the leading edge and the status capsule (TD-003) on the
/// trailing edge. They share one row, one plate height, one window inset, and
/// one bottom inset, so their bottom edges land on the same line. Neither
/// capsule keeps a private copy of these numbers: separate copies are exactly
/// how the two plates drifted onto two different lines.
public enum EditorStatusBarChrome: Sendable {
    /// Plate height for both capsules. It is also the smallest touch target, so
    /// the status capsule's controls keep 44 pt on iPhone.
    public static let controlMinHeight: CGFloat = 44
    /// Window edge to the outer edge of either capsule.
    public static let horizontalInset: CGFloat = 12
    /// Bottom safe area to the capsules' bottom edge. Applied once, to the shared
    /// row, never per capsule.
    public static let bottomInset: CGFloat = 6
    /// Smallest gap the row keeps between the two capsules. A narrower window
    /// truncates the sheet name instead of letting the plates touch.
    public static let capsuleGap: CGFloat = 8
    /// Width the sheet name may claim before it truncates with an ellipsis.
    public static let canvasTitleMaxWidth: CGFloat = 240
}

/// How the two bottom capsules share a narrow window. The status capsule is
/// measured, never guessed, and never compressed: the sheet name truncates
/// first, then the sheet capsule's divider goes, and the two plates never
/// overlap or push each other off screen.
public enum EditorBottomBarLayout {
    /// Narrowest the sheet capsule gets while it still draws its divider and a
    /// readable name: plate insets, the ▾ label, the ＋ button, the divider, and
    /// room for a truncated name.
    public static let minimumWidthWithDivider: CGFloat = 200

    /// The sheet capsule keeps its divider only while the row can still afford
    /// it beside the measured status capsule. `statusWidth == 0` means no status
    /// capsule is drawn at all.
    public static func showsSheetDivider(rowWidth: CGFloat, statusWidth: CGFloat) -> Bool {
        guard rowWidth > 0 else { return false }
        let reserved = statusWidth > 0 ? statusWidth + EditorStatusBarChrome.capsuleGap : 0
        let available = rowWidth - EditorStatusBarChrome.horizontalInset * 2 - reserved
        return available >= minimumWidthWithDivider
    }
}

/// Controls on the one bottom bar capsule, leading to trailing (TD-003).
/// The topic count opens the 主题 / 字数 / 字符数 breakdown; the numbers come from
/// `TopicTitleCensus`, so this list counts nothing. The presentation tab is
/// deliberately absent.
public enum EditorStatusControl: String, Equatable, Sendable {
    case topics
    case zoomMenu
    case viewMode
    case outline
    case immersive
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
        .topics,
        .zoomMenu,
        .viewMode,
        .outline,
        .immersive,
    ]

    /// Writes a menu stop into the chrome percent the editor already displays.
    /// `CanvasCamera.zoom(to:)` does this after it changes the viewport scale.
    /// Fit is left untouched: the camera fits the content, then syncs.
    public static func apply(_ choice: EditorStatusZoomChoice, to chrome: inout CanvasChrome) {
        guard let scale = choice.fixedScale else { return }
        chrome.syncZoomPercent(toScale: scale)
    }
}
