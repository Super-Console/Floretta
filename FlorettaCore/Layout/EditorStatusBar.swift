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
    /// Plate height for both capsules, matched to the platform's own control:
    /// 28 pt on the Mac, the same optical height as a native toolbar control, and
    /// the 44 pt touch target on iOS and iPadOS. Symbols stay 13 pt on both, so
    /// the plates sit level with the toolbar instead of a head taller.
    #if os(macOS)
    public static let controlMinHeight: CGFloat = 28
    #else
    public static let controlMinHeight: CGFloat = 44
    #endif
    /// Size of the SF Symbols the bottom capsules draw. Vector glyphs scale with
    /// this number, so every chrome icon has one weight and one size.
    public static let chromeFontSize: CGFloat = 13
    /// Square frame of one icon button inside the bottom capsules. The frame is
    /// also the hit target, so it never drops below `iconButtonHitMinSize`; the
    /// glyph inside keeps its `chromeFontSize` optical size, so a larger target
    /// does not draw a larger icon.
    public static let iconButtonSize: CGFloat = 28
    /// Floor for a chrome icon button's hit target, in points.
    public static let iconButtonHitMinSize: CGFloat = 28
    /// Horizontal padding inside the status capsule.
    public static let capsuleHorizontalPadding: CGFloat = 10
    /// Vertical padding inside the status capsule.
    public static let capsuleVerticalPadding: CGFloat = 3
    /// Spacing between the controls inside one group of the status capsule.
    public static let capsuleControlSpacing: CGFloat = 10
    /// Spacing between two groups of the status capsule. The hairline sits in
    /// the middle of this gap, so the gap is measured across the divider.
    public static let capsuleGroupSpacing: CGFloat = 16
    /// Width of the hairline that separates two groups.
    public static let capsuleSeparatorWidth: CGFloat = 1
    /// Height of that hairline: shorter than the plate, so it reads as a
    /// divider and not as a wall.
    public static let capsuleSeparatorHeight: CGFloat = 16
    /// Space each side of the hairline. Derived from the group gap and the
    /// hairline width, so the two groups sit exactly `capsuleGroupSpacing`
    /// apart without a second copy of that number.
    public static var capsuleSeparatorInset: CGFloat {
        (capsuleGroupSpacing - capsuleSeparatorWidth) / 2
    }
    /// Window edge to the outer edge of either capsule.
    public static let horizontalInset: CGFloat = 12
    /// Bottom safe area to the capsules' bottom edge. Applied once, to the shared
    /// row, never per capsule.
    public static let bottomInset: CGFloat = 6
    /// Smallest gap the row keeps between the two capsules. A narrower window
    /// truncates the sheet name instead of letting the plates touch.
    public static let capsuleGap: CGFloat = 8
    /// Share of the bottom row the sheet name may claim before it truncates.
    /// A window-relative cap keeps both capsules in proportion: a fixed cap
    /// left a short name stranded in a wide box, and let a wide window's
    /// capsule eat the row.
    public static let canvasTitleWidthFraction: CGFloat = 0.30
    /// Narrowest the sheet name is laid out at. A small window keeps a
    /// readable name instead of a couple of letters.
    public static let canvasTitleMinWidth: CGFloat = 120
    /// Widest the sheet name may claim, however wide the window is.
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

    /// Width the sheet name may claim in a row of `rowWidth`:
    /// `canvasTitleWidthFraction` of the row, clamped to the readability floor
    /// and the ceiling. The name is laid out at this width and truncates inside
    /// it, so a 60-character name can neither spill out of the capsule nor
    /// widen the bottom row. `rowWidth` is the measured bottom row — the same
    /// measurement the divider rule uses; 0 means "not measured yet".
    public static func canvasTitleWidthLimit(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return EditorStatusBarChrome.canvasTitleMinWidth }
        let share = rowWidth * EditorStatusBarChrome.canvasTitleWidthFraction
        return min(
            max(share, EditorStatusBarChrome.canvasTitleMinWidth),
            EditorStatusBarChrome.canvasTitleMaxWidth
        )
    }
}

/// Controls on the one bottom bar capsule, leading to trailing (TD-003).
/// The topic count opens the 主题 / 字数 / 字符数 breakdown; the numbers come from
/// `TopicTitleCensus`, so this list counts nothing. The presentation tab is
/// deliberately absent. `.pointerMode` is the Mac's 指针 / 手掌 tool; touch
/// platforms keep the pan drag they shipped with, so it is not drawn there.
public enum EditorStatusControl: String, Equatable, Sendable {
    case topics
    case pointerMode
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
    /// The capsule's controls, leading to trailing. The Mac adds the pointer /
    /// hand tool beside the view mode; iPhone and iPad draw the five they had.
    public static var controls: [EditorStatusControl] {
        #if os(macOS)
        return [
            .topics,
            .zoomMenu,
            .pointerMode,
            .viewMode,
            .outline,
            .immersive,
        ]
        #else
        return [
            .topics,
            .zoomMenu,
            .viewMode,
            .outline,
            .immersive,
        ]
        #endif
    }

    /// Writes a menu stop into the chrome percent the editor already displays.
    /// `CanvasCamera.zoom(to:)` does this after it changes the viewport scale.
    /// Fit is left untouched: the camera fits the content, then syncs.
    public static func apply(_ choice: EditorStatusZoomChoice, to chrome: inout CanvasChrome) {
        guard let scale = choice.fixedScale else { return }
        chrome.syncZoomPercent(toScale: scale)
    }
}
