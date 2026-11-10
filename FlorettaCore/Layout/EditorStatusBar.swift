import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Title word count and character count handed to the status capsule.
///
/// The status bar does not count text. A caller fills this only when a title
/// counter already exists. On this tree that counter is absent, so the capsule
/// keeps `MindMapDocument.topicCount` and omits 字数.
public struct TitleCountSupply: Equatable, Sendable {
    public var wordCount: Int
    public var characterCount: Int

    public init(wordCount: Int, characterCount: Int) {
        self.wordCount = wordCount
        self.characterCount = characterCount
    }
}

/// Where a future title counter plugs in.
///
/// Replace the body with that counter's word and character totals. Do not
/// count titles in this type.
public enum TitleCountSupplyReader {
    public static func supply(for _: MindMapDocument) -> TitleCountSupply? {
        nil
    }
}

/// Topic count plus the optional title census the capsule and its hover show.
public struct TopicCountCapsuleModel: Equatable, Sendable {
    public var topicCount: Int
    public var titles: TitleCountSupply?

    public init(topicCount: Int, titles: TitleCountSupply? = nil) {
        self.topicCount = topicCount
        self.titles = titles
    }

    public init(document: MindMapDocument, titles: TitleCountSupply? = nil) {
        self.init(topicCount: document.topicCount, titles: titles)
    }

    public var showsWordCount: Bool { titles != nil }

    /// Hover (or the tap equivalent). Nil when no title counter supplied a breakdown.
    public var breakdown: TopicCountBreakdown? {
        guard let titles else { return nil }
        return TopicCountBreakdown(
            topicCount: topicCount,
            wordCount: titles.wordCount,
            characterCount: titles.characterCount
        )
    }
}

/// The three figures a title counter reports: 主题数, 字数, 字符数.
public struct TopicCountBreakdown: Equatable, Sendable {
    public var topicCount: Int
    public var wordCount: Int
    public var characterCount: Int

    public init(topicCount: Int, wordCount: Int, characterCount: Int) {
        self.topicCount = topicCount
        self.wordCount = wordCount
        self.characterCount = characterCount
    }
}

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

/// Controls the bottom bar is allowed to host, in leading-to-trailing order.
public enum EditorStatusControl: String, Equatable, Sendable {
    case topicCapsule
    case zoomMenu
    case viewSwitcher
}

public enum EditorStatusBarModel {
    public static let controls: [EditorStatusControl] = [
        .topicCapsule,
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
