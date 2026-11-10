import FlorettaCore
import Foundation
import UniformTypeIdentifiers

/// Chrome for a `.md` document. The heading-depth preset stays on `FlorettaMarkdown`.
enum MarkdownModeCopy {
    static let title = "Markdown 模式"
    static let explanation = "本文件只保存层级与文字；不含附件、颜色、关系线、自由位置与折叠态。"
    /// The strip stays until the user upgrades and switches to the new `.floretta`.
    static let canDismiss = false
}

enum MarkdownBlockedControl: String, Equatable, CaseIterable, Sendable {
    case insertAttachment
    case insertImage
    case nodeColor
    case themeColor
    case copyStyle
    case relationship
    case freeNode
    case sticky
    case summary
    case boundary
    case collapse
    case tags
}

/// What a Markdown session may change, and which controls must stay disabled.
enum MarkdownModePolicy {
    static func isDocumentExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "md", "markdown":
            return true
        default:
            return false
        }
    }

    static func isEnabled(_ control: MarkdownBlockedControl, markdown: Bool) -> Bool {
        !markdown
    }

    /// One sentence per capability, reused by help, accessibilityHint, and the light tip.
    static func reason(_ control: MarkdownBlockedControl) -> String {
        switch control {
        case .insertAttachment, .insertImage:
            return "Markdown 模式无法保存附件"
        case .nodeColor, .themeColor, .copyStyle:
            return "Markdown 模式无法保存颜色"
        case .relationship:
            return "Markdown 模式无法保存关系线"
        case .freeNode:
            return "Markdown 模式无法保存自由位置"
        case .sticky:
            return "Markdown 模式无法保存便签"
        case .summary:
            return "Markdown 模式无法保存概要"
        case .boundary:
            return "Markdown 模式无法保存边界"
        case .collapse:
            return "Markdown 模式无法保存折叠态"
        case .tags:
            return "Markdown 模式无法保存标签"
        }
    }

    /// At most one notice for a successful open. Empty warnings produce nil.
    static func notice(for warnings: [FlorettaMarkdownDocumentWarning]) -> String? {
        var lines: [String] = []
        for warning in warnings {
            let message = warning.message
            if !lines.contains(message) {
                lines.append(message)
            }
        }
        if lines.isEmpty { return nil }
        return lines.joined(separator: "\n")
    }
}

/// Tree structure, text, note, link, section flags, and front-matter text.
/// Color, attachments, relationships, position, and collapse are not part of dirty state.
struct MarkdownPersistableProjection: Equatable, Sendable {
    var frontMatter: String?
    var roots: [Node]

    struct Node: Equatable, Sendable {
        var text: String
        var note: String
        var link: String?
        var isSection: Bool
        var children: [Node]
    }

    init(_ document: MindMapDocument) {
        frontMatter = document.markdownFrontMatter
        roots = document.roots.map(Node.init)
    }
}

extension MarkdownPersistableProjection.Node {
    init(_ node: MindMapNode) {
        text = node.text
        note = node.note
        let trimmed = node.link?.trimmingCharacters(in: .whitespacesAndNewlines)
        link = (trimmed?.isEmpty == false) ? trimmed : nil
        isSection = node.isMarkdownSectionHeading
        children = node.children.map(Self.init)
    }
}

/// The open-time normalization notice is produced once per session.
struct MarkdownWarningPresentation: Equatable, Sendable {
    private var surfaced = false

    mutating func present(_ notice: String?) -> String? {
        guard !surfaced else { return nil }
        surfaced = true
        return notice
    }
}

enum MarkdownUpgradeChoice: Equatable, Sendable {
    /// Default. The `.md` stays open.
    case keepMarkdown
    /// Switch the editor to the file the Save panel just wrote.
    case openFloretta
}

/// Save-panel payload for 「升级为完整工程」. Does not touch the open `.md`.
enum MarkdownUpgrade {
    static let defaultChoice = MarkdownUpgradeChoice.keepMarkdown
    static let actionTitle = "升级为完整工程"

    static var filenameExtension: String { FlorettaCodec.fileExtension }

    static var contentType: UTType {
        if let declared = UTType(FlorettaFileTypes.florettaIdentifier),
           declared.preferredFilenameExtension == FlorettaCodec.fileExtension {
            return declared
        }
        return UTType(filenameExtension: FlorettaCodec.fileExtension) ?? .data
    }

    /// Current tree plus default visual fields. Attachment lists are empty.
    static func fileData(for document: MindMapDocument) throws -> Data {
        try FlorettaCodec.encode(projected(document))
    }

    static func projected(_ document: MindMapDocument) -> MindMapDocument {
        var copy = document
        copy.freeNodes = []
        copy.relationships = []
        copy.stickies = []
        copy.additionalCanvases = []
        copy.xmindForeign = nil
        copy.opmlForeign = nil
        copy.mmForeign = nil
        copy.themeID = nil
        copy.roots = document.roots.map(cleaned)
        return copy
    }

    /// True when the Save panel destination is the open Markdown file.
    static func replacesOriginal(destination: URL, original: URL) -> Bool {
        destination.standardizedFileURL.path == original.standardizedFileURL.path
    }

    private static func cleaned(_ node: MindMapNode) -> MindMapNode {
        var copy = node
        copy.isCollapsed = false
        copy.style = nil
        copy.position = nil
        copy.side = nil
        copy.attachments = []
        copy.summaries = []
        copy.boundaries = []
        copy.labels = []
        copy.markers = []
        copy.children = node.children.map(cleaned)
        return copy
    }
}
