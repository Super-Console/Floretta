import Foundation

/// Inspector tabs that exist. There is no 演说 tab: the style work does not ship a
/// presentation surface, and an empty tab is not an entry point.
public enum InspectorTab: Int, CaseIterable, Identifiable, Sendable {
    case style = 0
    case map = 1

    public var id: Int { rawValue }

    public var titleKey: String {
        switch self {
        case .style: "样式"
        case .map: "导图"
        }
    }
}

/// Style-page groups in XMind's order. `shape` / `fill` / `border` / `width` / `text`
/// are written on the selected topic; `branch` / `colorScheme` / `background` /
/// `globalFont` are written on the document or the app profile and stay visible
/// with nothing selected. There is no `structure` case: the 结构 dropdown belongs
/// to the layout engine (TD-005) and must not appear until that engine exists.
public enum InspectorStyleSection: String, CaseIterable, Identifiable, Sendable {
    case shape
    case fill
    case border
    case width
    case text
    case branch
    case colorScheme
    case background
    case globalFont
    case links

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .shape: "形状"
        case .fill: "填充"
        case .border: "边框"
        case .width: "宽度"
        case .text: "文本"
        case .branch: "分支"
        case .colorScheme: "配色方案"
        case .background: "背景色"
        case .globalFont: "全局字体"
        case .links: "连到"
        }
    }

    /// True for the sections that do not need a selected topic.
    public var isDocumentScope: Bool {
        switch self {
        case .branch, .colorScheme, .background, .globalFont: true
        case .shape, .fill, .border, .width, .text, .links: false
        }
    }
}

/// `PX` pins `topicWidth`; `适应` lets the measured text set the width.
public enum InspectorWidthMode: String, CaseIterable, Identifiable, Sendable {
    case pixels
    case fit

    public var id: String { rawValue }

    public var titleKey: String {
        self == .pixels ? "PX" : "适应"
    }
}

public enum InspectorTopicShape: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case rounded
    case capsule
    case none

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .rectangle: "矩形"
        case .rounded: "圆角"
        case .capsule: "胶囊"
        case .none: "无边框"
        }
    }

    /// Radii the style picker already wrote. `none` is a cleared corner, not a new shape.
    public var cornerRadius: Double {
        switch self {
        case .rectangle: 2
        case .rounded: 8
        case .capsule: 40
        case .none: 0
        }
    }
}

public enum InspectorFillStyle: String, CaseIterable, Identifiable, Sendable {
    case solid
    case none

    public var id: String { rawValue }

    public var titleKey: String {
        self == .solid ? "实心" : "无"
    }
}

public enum InspectorBorderStyle: String, CaseIterable, Identifiable, Sendable {
    case solid
    case none

    public var id: String { rawValue }

    public var titleKey: String {
        self == .solid ? "实线" : "无"
    }
}

public enum InspectorFontDesign: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case serif
    case rounded
    case monospaced

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .default: "系统"
        case .serif: "衬线"
        case .rounded: "圆体"
        case .monospaced: "等宽"
        }
    }
}

public enum InspectorTextFlag: String, CaseIterable, Identifiable, Sendable {
    case bold
    case italic
    case strikethrough
    case underline

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .bold: "粗体"
        case .italic: "斜体"
        case .strikethrough: "删除线"
        case .underline: "下划线"
        }
    }

    /// The mark drawn by the system button. Not a separate setting.
    public var mark: String {
        switch self {
        case .bold: "B"
        case .italic: "I"
        case .strikethrough: "S"
        case .underline: "U"
        }
    }
}

/// What the border-width row shows. `none` is the existing zero-width border, not a new control.
public enum InspectorBorderWidthReadout: Equatable, Sendable {
    case none
    case points(Double)
}

/// One write from a system control. The view does not keep a second copy of these fields.
public enum InspectorStyleEdit: Equatable, Sendable {
    case shape(InspectorTopicShape)
    case fillStyle(InspectorFillStyle)
    case fillHex(String)
    case topicWidth(Double)
    case borderStyle(InspectorBorderStyle)
    case borderWidth(Double)
    case borderHex(String)
    case fontDesign(InspectorFontDesign)
    case fontSize(Double)
    case textHex(String)
    case flag(InspectorTextFlag, Bool)
    case widthMode(InspectorWidthMode)
}

/// One write that lands on the document instead of a topic. Same contract as
/// `InspectorStyleEdit`: the view keeps no second copy of these fields.
public enum InspectorDocumentStyleEdit: Equatable, Sendable {
    case branchLine(BranchLineStyle)
    case branchEnd(BranchEndMarker)
    case colorScheme(String?)
}

public struct InspectorMapFacts: Equatable, Sendable {
    public var attachmentBytes: Int64
    public var archiveBytes: Int64
    public var referenceCount: Int
    public var topicCount: Int
    public var stickyCount: Int
    public var relationshipCount: Int
    public var summaryCount: Int
    public var boundaryCount: Int

    public init(
        attachmentBytes: Int64,
        archiveBytes: Int64,
        referenceCount: Int,
        topicCount: Int,
        stickyCount: Int,
        relationshipCount: Int,
        summaryCount: Int,
        boundaryCount: Int
    ) {
        self.attachmentBytes = attachmentBytes
        self.archiveBytes = archiveBytes
        self.referenceCount = referenceCount
        self.topicCount = topicCount
        self.stickyCount = stickyCount
        self.relationshipCount = relationshipCount
        self.summaryCount = summaryCount
        self.boundaryCount = boundaryCount
    }
}

/// Document edits behind the inspector. Called when a control changes, not on a timer.
public enum InspectorStyle {
    public static let sections = InspectorStyleSection.allCases
    public static let mapRowTitleKeys = [
        "附件合计", "文档大小", "引用", "节点", "便签", "关系", "概要", "边界",
    ]

    public static let topicWidthRange: ClosedRange<Double> = 40...480
    public static let borderWidthRange: ClosedRange<Double> = 0...8
    public static let fontSizeRange: ClosedRange<Double> = 10...64
    public static let fontSizeStep: Double = 1

    public static let defaultTopicWidth: Double = 120
    public static let defaultBorderWidth: Double = 1.5
    public static let defaultFontSize: Double = 18
    public static let fallbackColorHex = "#000000"
    public static let fallbackFillHex = "#FFFFFF"

    /// Known tags, plus the stored value when a file brought a style this picker does not name.
    /// The extra tag is that stored string, so opening the inspector does not overwrite it.
    public static func choiceTags(known: [String], current: String) -> [String] {
        if known.contains(current) { return known }
        return known + [current]
    }

    public static func shape(of style: MindMapNodeStyle?) -> InspectorTopicShape {
        guard let radius = style?.cornerRadius else { return .rounded }
        if radius <= 0 { return .none }
        if radius >= 24 { return .capsule }
        if radius <= 3 { return .rectangle }
        return .rounded
    }

    public static func fillStyleValue(of style: MindMapNodeStyle?) -> String {
        style?.fillStyle ?? InspectorFillStyle.solid.rawValue
    }

    public static func borderStyleValue(of style: MindMapNodeStyle?) -> String {
        style?.borderStyle ?? InspectorBorderStyle.solid.rawValue
    }

    public static func fontDesignValue(of style: MindMapNodeStyle?) -> String {
        style?.fontDesign ?? InspectorFontDesign.default.rawValue
    }

    public static func topicWidthValue(of style: MindMapNodeStyle?) -> Double {
        style?.topicWidth ?? defaultTopicWidth
    }

    public static func widthMode(of style: MindMapNodeStyle?) -> InspectorWidthMode {
        style?.autoWidth == true ? .fit : .pixels
    }

    public static func branchLineValue(of document: MindMapDocument) -> BranchLineStyle {
        BranchStyle.line(document.branchLineStyle)
    }

    public static func branchEndValue(of document: MindMapDocument) -> BranchEndMarker {
        BranchStyle.endMarker(document.branchEndMarker)
    }

    /// The stored id, or the standard scheme the layout falls back to.
    public static func colorSchemeValue(of document: MindMapDocument) -> String {
        MapThemeCatalog.persistedID(document.themeID) ?? MapThemeCatalog.standardID
    }

    /// Six color presets, then the branch themes. Same ids the 配色 sheet lists.
    public static var colorSchemeChoiceIDs: [String] {
        MapColorPresetCatalog.all.map(\.id) + MapThemeCatalog.all.map(\.id)
    }

    /// Nil for an id neither catalog knows, so a newer preset still round-trips
    /// and the picker can show its raw id instead of inventing a name.
    public static func colorSchemeNameKey(_ id: String) -> String? {
        if let preset = MapColorPresetCatalog.all.first(where: { $0.id == id }) {
            return preset.nameKey
        }
        return MapThemeCatalog.all.first(where: { $0.id == id })?.nameKey
    }

    public static func borderWidthValue(of style: MindMapNodeStyle?) -> Double {
        style?.borderWidth ?? defaultBorderWidth
    }

    public static func fontSizeValue(of style: MindMapNodeStyle?) -> Double {
        style?.fontSize ?? defaultFontSize
    }

    public static func isOn(_ flag: InspectorTextFlag, style: MindMapNodeStyle?) -> Bool {
        switch flag {
        case .bold: style?.bold ?? false
        case .italic: style?.italic ?? false
        case .strikethrough: style?.strikethrough ?? false
        case .underline: style?.underline ?? false
        }
    }

    public static func borderWidthReadout(of style: MindMapNodeStyle?) -> InspectorBorderWidthReadout {
        let width = borderWidthValue(of: style)
        if borderStyleValue(of: style) == InspectorBorderStyle.none.rawValue || width == 0 {
            return .none
        }
        return .points(width)
    }

    public static func links(in document: MindMapDocument, nodeID: UUID) -> [TopicRelationship] {
        document.relationships.filter { $0.sourceID == nodeID || $0.targetID == nodeID }
    }

    public static func relationshipLine(
        _ link: TopicRelationship,
        seenFrom id: UUID,
        document: MindMapDocument,
        missingTopic: String
    ) -> String {
        let otherID = link.sourceID == id ? link.targetID : link.sourceID
        let name = document.node(otherID)?.text ?? missingTopic
        if link.title.isEmpty { return name }
        return "\(name) · \(link.title)"
    }

    /// Commits an open edit, then selects the relationship. Topic selection clears as a result.
    public static func selectLink(
        _ id: UUID,
        document: inout MindMapDocument,
        keyboard: inout MindMapKeyboardSession
    ) {
        if keyboard.mode == .edit {
            keyboard.apply(.commitEdit, document: &document, frames: [])
        }
        keyboard.selectedRelationshipID = id
    }

    public static func mapFacts(
        document: MindMapDocument,
        storedAttachmentBytes: Int64,
        archiveByteCount: Int64
    ) -> InspectorMapFacts {
        let references = AttachmentReferences.counts(in: document)
        let referencedBytes = references.reduce(Int64(0)) { $0 + $1.byteCount }
        let total = storedAttachmentBytes > 0 ? storedAttachmentBytes : referencedBytes
        return InspectorMapFacts(
            attachmentBytes: total,
            archiveBytes: archiveByteCount,
            referenceCount: references.reduce(0) { $0 + $1.count },
            topicCount: document.topicCount,
            stickyCount: document.stickies.count,
            relationshipCount: document.relationships.count,
            summaryCount: document.summaryCount,
            boundaryCount: document.boundaryCount
        )
    }

    public static func mapValue(_ key: String, facts: InspectorMapFacts) -> String {
        switch key {
        case "附件合计": return AttachmentByteFormat.label(facts.attachmentBytes)
        case "文档大小": return AttachmentByteFormat.label(facts.archiveBytes)
        case "引用": return "\(facts.referenceCount)"
        case "节点": return "\(facts.topicCount)"
        case "便签": return "\(facts.stickyCount)"
        case "关系": return "\(facts.relationshipCount)"
        case "概要": return "\(facts.summaryCount)"
        case "边界": return "\(facts.boundaryCount)"
        default: return ""
        }
    }

    @discardableResult
    public static func apply(
        _ edit: InspectorStyleEdit,
        nodeID: UUID,
        document: inout MindMapDocument,
        allowsAppearanceWrites: Bool
    ) -> Bool {
        guard allowsAppearanceWrites else { return false }
        if case .fillHex(let hex) = edit {
            return document.mutateNode(nodeID) { node in
                var style = node.style ?? MindMapNodeStyle(colorHex: hex)
                style.fillHex = hex
                style.colorHex = hex
                style.fillStyle = InspectorFillStyle.solid.rawValue
                node.style = style
            }
        }
        return document.mutateNode(nodeID) { node in
            var style = node.style ?? MindMapNodeStyle(colorHex: fallbackColorHex)
            write(edit, into: &style)
            node.style = style
        }
    }

    /// Document-scope writes: branch line/end tokens and the color scheme id.
    @discardableResult
    public static func applyDocument(
        _ edit: InspectorDocumentStyleEdit,
        document: inout MindMapDocument,
        allowsAppearanceWrites: Bool
    ) -> Bool {
        guard allowsAppearanceWrites else { return false }
        switch edit {
        case .branchLine(let line):
            let stored = BranchStyle.persistedLine(line)
            guard document.branchLineStyle != stored else { return false }
            document.branchLineStyle = stored
        case .branchEnd(let marker):
            let stored = BranchStyle.persistedEndMarker(marker)
            guard document.branchEndMarker != stored else { return false }
            document.branchEndMarker = stored
        case .colorScheme(let id):
            let stored = MapThemeCatalog.persistedID(id)
            guard MapThemeCatalog.persistedID(document.themeID) != stored else { return false }
            document.themeID = stored
        }
        return true
    }

    private static func write(_ edit: InspectorStyleEdit, into style: inout MindMapNodeStyle) {
        switch edit {
        case .fillHex:
            break
        case .shape(let shape):
            style.cornerRadius = shape.cornerRadius
            if shape == .none {
                style.borderWidth = 0
                style.borderStyle = InspectorBorderStyle.none.rawValue
            }
        case .fillStyle(let fill):
            style.fillStyle = fill.rawValue
        case .widthMode(let mode):
            style.autoWidth = mode == .fit
            // 适应 keeps the last px width, so switching back restores the value.
            if mode == .pixels, style.topicWidth == nil {
                style.topicWidth = defaultTopicWidth
            }
        case .topicWidth(let width):
            style.topicWidth = width
            style.autoWidth = false
        case .borderStyle(let border):
            style.borderStyle = border.rawValue
            if border == .none { style.borderWidth = 0 }
        case .borderWidth(let width):
            style.borderWidth = width
            style.borderStyle = width == 0
                ? InspectorBorderStyle.none.rawValue
                : InspectorBorderStyle.solid.rawValue
        case .borderHex(let hex):
            style.borderHex = hex
        case .fontDesign(let design):
            style.fontDesign = design.rawValue
        case .fontSize(let size):
            style.fontSize = size
        case .textHex(let hex):
            style.textHex = hex
        case .flag(let flag, let isOn):
            switch flag {
            case .bold: style.bold = isOn
            case .italic: style.italic = isOn
            case .strikethrough: style.strikethrough = isOn
            case .underline: style.underline = isOn
            }
        }
    }
}

/// Text fields for the relationship, summary, and boundary inspector pages.
public enum InspectorMarkKind: Equatable, Sendable {
    case relationship
    case summary
    case boundary
}

public enum InspectorMarkField {
    public static func text(
        _ kind: InspectorMarkKind,
        id: UUID?,
        document: MindMapDocument,
        keyboard: MindMapKeyboardSession
    ) -> String {
        guard let id else { return "" }
        switch kind {
        case .relationship:
            if keyboard.editingRelationshipID == id { return keyboard.editingText }
            return document.relationship(id)?.title ?? ""
        case .summary:
            if keyboard.editingSummaryID == id { return keyboard.editingText }
            return document.summary(id)?.text ?? ""
        case .boundary:
            if keyboard.editingBoundaryID == id { return keyboard.editingText }
            return document.boundary(id)?.title ?? ""
        }
    }

    public static func replace(
        _ newValue: String,
        kind: InspectorMarkKind,
        id: UUID?,
        document: inout MindMapDocument,
        keyboard: inout MindMapKeyboardSession
    ) {
        guard let id, selectionMatches(kind, id: id, keyboard: keyboard) else { return }
        let editingID: UUID?
        switch kind {
        case .relationship: editingID = keyboard.editingRelationshipID
        case .summary: editingID = keyboard.editingSummaryID
        case .boundary: editingID = keyboard.editingBoundaryID
        }
        if editingID != id {
            keyboard.apply(.beginEdit, document: &document, frames: [])
        }
        keyboard.replaceEditingText(newValue, document: &document)
    }

    public static func commit(
        document: inout MindMapDocument,
        keyboard: inout MindMapKeyboardSession
    ) {
        guard keyboard.mode == .edit else { return }
        keyboard.apply(.commitEdit, document: &document, frames: [])
    }

    private static func selectionMatches(
        _ kind: InspectorMarkKind,
        id: UUID,
        keyboard: MindMapKeyboardSession
    ) -> Bool {
        switch kind {
        case .relationship: keyboard.selectedRelationshipID == id
        case .summary: keyboard.selectedSummaryID == id
        case .boundary: keyboard.selectedBoundaryID == id
        }
    }
}
