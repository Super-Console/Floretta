import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Decides which editor-chrome writes are allowed to run again.
///
/// A node double-click on macOS enters text editing and refreshes toolbar
/// enablement while AppKit is inside `layoutSubtreeIfNeeded`. Two writes were
/// re-entered from that layout pass and never compared equal, so
/// `DocumentEditor.body` ran again with no tracked state change:
///
/// - `NSWindow.titleVisibility` / `NSToolbar.displayMode` were assigned from
///   `NSView.layout`. SwiftUI rebuilds toolbar items (preferences and named
///   images) as part of that same layout. Putting the display mode back
///   invalidates the toolbar, which lays out again.
/// - The field assigned its font whenever `NSFont`/`UIFont` inequality failed.
///   A cascade face used for CJK text does not round-trip through AppKit's
///   font substitution, so the same request was written on every pass.
/// - Vertical centering derived the next inset from a used-rect that itself
///   depends on the inset, so the inset could step by more than half a point
///   forever.
///
/// Each gate below latches. A later layout pass with the same inputs must not
/// write. A blank-canvas double-click never opens the field and does not
/// refresh toolbar enablement, which is why that path stayed in the event loop.
public struct EditingFontSignature: Equatable, Sendable {
    public var familyID: String
    public var design: String
    public var size: CGFloat
    public var bold: Bool
    public var italic: Bool

    public init(familyID: String, design: String, size: CGFloat, bold: Bool, italic: Bool) {
        self.familyID = familyID
        self.design = design
        self.size = size
        self.bold = bold
        self.italic = italic
    }
}

public struct TextCenteringPass: Equatable, Sendable {
    public var bounds: CGSize
    public var text: String

    public static let idle = TextCenteringPass(bounds: .zero, text: "")

    public init(bounds: CGSize, text: String) {
        self.bounds = bounds
        self.text = text
    }

    /// One centering write per field size and string. The inset assignment
    /// invalidates layout; doing it again for the same inputs does not.
    public func shouldApply(to bounds: CGSize, text: String) -> Bool {
        guard bounds.width > 1, bounds.height > 1,
              bounds.width.isFinite, bounds.height.isFinite else { return false }
        return self.bounds != bounds || self.text != text
    }
}

public struct WindowChromeWrite: Equatable, Sendable {
    public var hideTitle: Bool
    public var forceIconOnly: Bool

    public init(hideTitle: Bool, forceIconOnly: Bool) {
        self.hideTitle = hideTitle
        self.forceIconOnly = forceIconOnly
    }
}

/// Latches the first window-chrome correction. Later passes must not chase a
/// title or toolbar mode that SwiftUI puts back during layout.
public struct WindowChromePass: Equatable, Sendable {
    public var hidTitle = false
    public var forcedIconOnly = false

    public init() {}

    public mutating func applying(
        titleIsHidden: Bool,
        hasToolbar: Bool,
        toolbarIsIconOnly: Bool
    ) -> WindowChromeWrite {
        var hideTitle = false
        if !hidTitle {
            hidTitle = true
            hideTitle = !titleIsHidden
        }
        var forceIconOnly = false
        if !forcedIconOnly, hasToolbar {
            forcedIconOnly = true
            forceIconOnly = !toolbarIsIconOnly
        }
        return WindowChromeWrite(hideTitle: hideTitle, forceIconOnly: forceIconOnly)
    }
}

public enum EditorLayoutConvergence {
    /// True only when this request has not already been given to the field.
    /// Font-object inequality is not an input: substitution keeps that false.
    public static func shouldAssignFont(
        requested: EditingFontSignature,
        lastAssigned: EditingFontSignature?
    ) -> Bool {
        lastAssigned != requested
    }

    /// Whole points. The caller supplies the font's default line height, which
    /// is independent of the text container inset returned here.
    public static func centeredVerticalInset(boundsHeight: CGFloat, glyphHeight: CGFloat) -> CGFloat {
        guard boundsHeight.isFinite, glyphHeight.isFinite, boundsHeight > 0 else { return 0 }
        let glyphs = min(max(glyphHeight, 0), boundsHeight)
        return ((boundsHeight - glyphs) / 2).rounded()
    }

    public static func shouldWriteVerticalInset(current: CGFloat, proposed: CGFloat) -> Bool {
        guard current.isFinite, proposed.isFinite else { return false }
        return abs(current - proposed) > 0.5
    }
}
