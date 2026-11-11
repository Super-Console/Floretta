import Foundation

/// Where a command is drawn. The toolbar face is icon-only. An opened menu row
/// is the SF Symbol plus the title. Same rule on Mac and iOS.
public enum EditorCommandSurface: Equatable, Sendable {
    case toolbar
    case expandedMenu
}

public enum EditorCommandDisplay: Equatable, Sendable {
    case iconOnly
    case iconAndTitle
}

/// Zoom keeps the live percent in the toolbar. Every other command uses its symbol there.
public enum EditorToolbarFace: Equatable, Sendable {
    case symbol
    case zoomPercent
}

public enum EditorCommandKind: Equatable, Sendable {
    case button
    case submenu
    case pulldown
}

public enum EditorCommandMenu: String, Equatable, Sendable {
    case insert
    case share
    case more
    case viewMode
    case zoom
}

public enum EditorCommandAvailability: Equatable, Sendable {
    case always
    case notWhileComposing
    case notInMarkdown
    case requiresSelectedTopic
    case requiresEnclosableTopic
    case requiresSavedPackage
}

/// `visible` is on the toolbar until the person removes it.
/// `addable` starts in the customization palette.
/// `menuOnly` stays inside a menu and is not its own toolbar item.
public enum EditorCommandCustomization: Equatable, Sendable {
    case visible
    case addable
    case menuOnly
}

public enum EditorToolbarPlacement: Equatable, Sendable {
    case principal
    case primary
}

public enum EditorToolbarCommandID: String, CaseIterable, Equatable, Sendable {
    case undo
    case redo
    case delete
    case insert
    case share
    case zoom
    case immersive
    case more
    case child
    case sibling
    case dictation
    case freeNode
    case sticky
    case link
    case summary
    case boundary
    case region
    case image
    case attachment
    case importFile
    case outline
    case style
    case theme
    case viewMode
    case mapMode
    case focusMode
    case newCanvas
    case find
    case tagFilter
    case history
    case paste
    case about
    case fit
    case pdf
    case png
    case markdownExport
    case textBundle
    case saveFloretta
    case upgrade
    case mm
    case opml
    case xmind
    case printMap
}

public struct EditorToolbarCommand: Equatable, Sendable, Identifiable {
    public var id: EditorToolbarCommandID
    public var title: String
    public var symbol: String
    public var help: String
    public var availability: EditorCommandAvailability
    public var kind: EditorCommandKind
    public var menu: EditorCommandMenu?
    public var customization: EditorCommandCustomization
    public var placement: EditorToolbarPlacement
    public var toolbarFace: EditorToolbarFace
}

/// Flags the editor already has. Enablement does not walk the canvas.
public struct EditorToolbarContext: Equatable, Sendable {
    public var isMarkdownDocument: Bool
    public var isComposing: Bool
    public var hasSelectedTopic: Bool
    public var canEncloseSelection: Bool
    public var canOpenSnapshotHistory: Bool

    public init(
        isMarkdownDocument: Bool = false,
        isComposing: Bool = false,
        hasSelectedTopic: Bool = false,
        canEncloseSelection: Bool = false,
        canOpenSnapshotHistory: Bool = false
    ) {
        self.isMarkdownDocument = isMarkdownDocument
        self.isComposing = isComposing
        self.hasSelectedTopic = hasSelectedTopic
        self.canEncloseSelection = canEncloseSelection
        self.canOpenSnapshotHistory = canOpenSnapshotHistory
    }
}

public struct EditorCommandPresentation: Equatable, Sendable {
    public var symbol: String
    public var title: String
    public var showsSymbol: Bool
    public var showsTitle: Bool
    public var showsZoomPercent: Bool
    public var isEnabled: Bool
    /// Disabled commands stay in the menu. This does not become false when `isEnabled` does.
    public var isListed: Bool
}

/// Titles, SF Symbols, and enabled-when for toolbar commands.
/// Lookups are a fixed table. Nothing here runs from the canvas frame loop.
public enum EditorToolbarCatalog {
    public static let commands: [EditorToolbarCommand] = [
        item(.undo, "撤销", "arrow.uturn.backward", "撤销上一步编辑", customization: .visible, placement: .principal),
        item(.redo, "重做", "arrow.uturn.forward", "恢复刚刚撤销的编辑", customization: .visible, placement: .principal),
        item(.delete, "删除", "trash", "删除选中的节点、便签、关系、概要、边界或专区", customization: .visible, placement: .principal),
        item(.insert, "插入", "plus", "插入子节点、同级、语音输入、自由节点、便签、概要、边界、专区、图片、附件，或从文件导入", kind: .pulldown, customization: .visible),
        item(.share, "分享", "square.and.arrow.up", "把导图导出为 PDF、PNG、Markdown，或保存为已支持的文件", kind: .pulldown, customization: .visible),
        item(.zoom, "缩放", "plus.magnifyingglass", "选择缩放比例，或让导图适应窗口", kind: .pulldown, customization: .visible, toolbarFace: .zoomPercent),
        item(.immersive, "全屏沉浸", "rectangle.expand.diagonal", "进入全屏沉浸模式，暂时只留下导图", customization: .visible),
        item(.more, "更多", "ellipsis", "大纲、样式、配色、查找、标签筛选、版本历史、粘贴和关于", kind: .pulldown, customization: .visible),

        item(.child, "子节点", "plus.square", "在选中的节点下新建一个子节点", menu: .insert, customization: .addable),
        item(.sibling, "同级", "square.on.square", "在选中的节点旁新建一个同级节点", menu: .insert, customization: .addable),
        item(.dictation, "语音输入", "mic", "用系统听写新建子节点。正在编辑或选中自由节点时，听写写进当前文字。", availability: .notWhileComposing, menu: .insert, customization: .addable),
        item(.freeNode, "自由节点", "arrow.up.left.and.arrow.down.right", "在画布上放一个不进层级的节点，位置会保存", availability: .notInMarkdown, menu: .insert, customization: .addable),
        item(.sticky, "便签", "note.text", "在画布上放一张便签。最多五种颜色，不计入节点，可以拖动，大小有上限", availability: .notInMarkdown, menu: .insert, customization: .addable),
        item(.link, "连到", "point.topleft.down.to.point.bottomright.curvepath", "把选中的节点连到另一个节点，画布上会画出这条线。", availability: .requiresSelectedTopic, kind: .submenu, menu: .insert, customization: .addable),
        item(.summary, "概要", "curlybraces", "为选中的节点生成概要，并画出括住它的括号", availability: .requiresEnclosableTopic, menu: .insert, customization: .addable),
        item(.boundary, "边界", "rectangle.dashed", "用边界圈住选中的节点", availability: .requiresEnclosableTopic, menu: .insert, customization: .addable),
        item(.region, "专区", "rectangle", "在画布上放一个矩形区域。它可以圈住节点，但不会改变节点层级。", availability: .notInMarkdown, menu: .insert, customization: .addable),
        item(.image, "图片", "photo", "从文件选择一张图片放进选中的节点", availability: .notInMarkdown, menu: .insert, customization: .addable),
        item(.attachment, "附件", "paperclip", "把一个文件原样放进选中的节点", availability: .notInMarkdown, menu: .insert, customization: .addable),
        item(.importFile, "从文件导入", "folder", "从文件打开另一份导图", menu: .insert, customization: .addable),

        item(.outline, "大纲", "list.bullet", "打开或关闭左侧大纲", menu: .more, customization: .addable),
        item(.style, "样式", "paintbrush", "打开样式检查器，修改选中节点的外观", availability: .notInMarkdown, menu: .more, customization: .addable),
        item(.theme, "配色", "paintpalette", "为各分支自动配色，浅色和深色各用一套", availability: .notInMarkdown, menu: .more, customization: .addable),
        item(.viewMode, "查看模式", "eye", "在地图模式和聚焦模式之间切换", kind: .submenu, customization: .addable),
        item(.newCanvas, "新建画布", "plus.rectangle.on.rectangle", "在这份导图里再加一个中心主题", customization: .addable),
        item(.find, "查找", "magnifyingglass", "按文字或标签查找节点", menu: .more, customization: .addable),
        item(.tagFilter, "标签筛选", "tag", "给选中的主题加上优先级、进度、旗帜或标签，并按标签高亮", availability: .notInMarkdown, menu: .more, customization: .addable),
        item(.history, "版本历史", "clock.arrow.circlepath", "查看已保存的历史版本，回滚或对比两份内容。", availability: .requiresSavedPackage, menu: .more, customization: .addable),
        item(.paste, "粘贴", "doc.on.clipboard", "把剪贴板里的图片放进节点；没有图片时粘贴文字", menu: .more, customization: .addable),
        item(.about, "关于", "info.circle", "查看版本号和开源致谢", menu: .more, customization: .addable),

        item(.mapMode, "地图模式", "map", "用整张地图查看导图", menu: .viewMode, customization: .addable),
        item(.focusMode, "聚焦模式", "scope", "只看当前选中的这一支", menu: .viewMode, customization: .addable),
        item(.fit, "适应窗口", "viewfinder", "让整张导图缩进窗口里", menu: .zoom, customization: .addable),

        item(.pdf, "PDF", "doc.richtext", "把这份导图导出为 PDF", menu: .share, customization: .menuOnly),
        item(.png, "PNG", "photo", "把这份导图导出为 PNG 图片", menu: .share, customization: .menuOnly),
        item(.markdownExport, "Markdown", "doc.plaintext", "把这份导图导出为 Markdown", menu: .share, customization: .menuOnly),
        item(.textBundle, "TextBundle…", "doc.zipper", "把这份导图导出为 TextBundle", menu: .share, customization: .menuOnly),
        item(.saveFloretta, "保存为 Floretta", "square.and.arrow.down", "把这份导图保存为 Floretta 文件", menu: .share, customization: .menuOnly),
        item(.upgrade, "升级为完整工程", "arrow.up.document", "把当前导图另存为 Floretta 工程。原来的 Markdown 文件不会被改掉。", menu: .share, customization: .menuOnly),
        item(.mm, ".mm", "doc", "把这份导图导出为 FreeMind .mm", menu: .share, customization: .menuOnly),
        item(.opml, "OPML", "list.bullet", "把这份导图导出为 OPML", menu: .share, customization: .menuOnly),
        item(.xmind, ".xmind", "square.stack.3d.up", "导出为 XMind，自由节点写成浮动主题", menu: .share, customization: .menuOnly),
        item(.printMap, "打印", "printer", "打印这份导图", menu: .share, customization: .menuOnly),
    ]

    private static let byID: [EditorToolbarCommandID: EditorToolbarCommand] = {
        var map: [EditorToolbarCommandID: EditorToolbarCommand] = [:]
        map.reserveCapacity(commands.count)
        for command in commands {
            map[command.id] = command
        }
        return map
    }()

    public static func command(_ id: EditorToolbarCommandID) -> EditorToolbarCommand {
        guard let command = byID[id] else {
            preconditionFailure("Missing toolbar command \(id.rawValue)")
        }
        return command
    }

    public static func menu(_ menu: EditorCommandMenu) -> [EditorToolbarCommandID] {
        commands.compactMap { $0.menu == menu ? $0.id : nil }
    }

    public static var defaultToolbarItems: [EditorToolbarCommandID] {
        commands.compactMap { $0.customization == .visible ? $0.id : nil }
    }

    public static var addableToolbarItems: [EditorToolbarCommandID] {
        commands.compactMap { $0.customization == .addable ? $0.id : nil }
    }

    public static func display(on surface: EditorCommandSurface) -> EditorCommandDisplay {
        switch surface {
        case .toolbar:
            return .iconOnly
        case .expandedMenu:
            return .iconAndTitle
        }
    }

    public static func isEnabled(_ id: EditorToolbarCommandID, in context: EditorToolbarContext) -> Bool {
        switch command(id).availability {
        case .always:
            return true
        case .notWhileComposing:
            return !context.isComposing
        case .notInMarkdown:
            return !context.isMarkdownDocument
        case .requiresSelectedTopic:
            return !context.isMarkdownDocument && context.hasSelectedTopic
        case .requiresEnclosableTopic:
            return !context.isMarkdownDocument && context.canEncloseSelection
        case .requiresSavedPackage:
            return context.canOpenSnapshotHistory
        }
    }

    public static func presentation(
        _ id: EditorToolbarCommandID,
        on surface: EditorCommandSurface,
        in context: EditorToolbarContext
    ) -> EditorCommandPresentation {
        let command = command(id)
        let enabled = isEnabled(id, in: context)
        switch surface {
        case .toolbar where command.toolbarFace == .zoomPercent:
            return EditorCommandPresentation(
                symbol: command.symbol,
                title: command.title,
                showsSymbol: false,
                showsTitle: false,
                showsZoomPercent: true,
                isEnabled: enabled,
                isListed: true
            )
        case .toolbar:
            return EditorCommandPresentation(
                symbol: command.symbol,
                title: command.title,
                showsSymbol: !command.symbol.isEmpty,
                showsTitle: false,
                showsZoomPercent: false,
                isEnabled: enabled,
                isListed: true
            )
        case .expandedMenu:
            return EditorCommandPresentation(
                symbol: command.symbol,
                title: command.title,
                showsSymbol: !command.symbol.isEmpty,
                showsTitle: !command.title.isEmpty,
                showsZoomPercent: false,
                isEnabled: enabled,
                isListed: true
            )
        }
    }

    private static func item(
        _ id: EditorToolbarCommandID,
        _ title: String,
        _ symbol: String,
        _ help: String,
        availability: EditorCommandAvailability = .always,
        kind: EditorCommandKind = .button,
        menu: EditorCommandMenu? = nil,
        customization: EditorCommandCustomization,
        placement: EditorToolbarPlacement = .primary,
        toolbarFace: EditorToolbarFace = .symbol
    ) -> EditorToolbarCommand {
        EditorToolbarCommand(
            id: id,
            title: title,
            symbol: symbol,
            help: help,
            availability: availability,
            kind: kind,
            menu: menu,
            customization: customization,
            placement: placement,
            toolbarFace: toolbarFace
        )
    }
}
