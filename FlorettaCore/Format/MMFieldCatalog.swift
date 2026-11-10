import Foundation

public enum MMFieldDisposition: String, Equatable, Sendable {
    case mapped
    case passthrough
    case gap
}

public struct MMFieldRow: Equatable, Sendable {
    public var field: String
    public var disposition: MMFieldDisposition
    public var detail: String

    public init(field: String, disposition: MMFieldDisposition, detail: String) {
        self.field = field
        self.disposition = disposition
        self.detail = detail
    }
}

public struct MMFixtureClass: Equatable, Sendable {
    public var name: String
    public var file: String
    public var detail: String

    public init(name: String, file: String, detail: String) {
        self.name = name
        self.file = file
        self.detail = detail
    }
}

/// Field comparison for FreeMind `.mm`. `docs/MM-FIELDS.md` mirrors these rows.
public enum MMFieldCatalog {
    public static let fixtures: [MMFixtureClass] = [
        MMFixtureClass(name: "simple", file: "simple.mm", detail: "单根、两个子节点"),
        MMFixtureClass(name: "nested", file: "nested.mm", detail: "五层，折叠、左右侧、链接和备注"),
        MMFixtureClass(name: "passthrough", file: "passthrough.mm", detail: "图标、字体、边、云、箭头、颜色、富文本标记和 DETAILS"),
    ]

    public static let rows: [MMFieldRow] = [
        MMFieldRow(field: "source bytes", disposition: .passthrough, detail: "映射快照没变时，导出就是导入的原字节"),
        MMFieldRow(field: "map attributes", disposition: .passthrough, detail: "version 和其他 map 属性写回"),
        MMFieldRow(field: "TEXT", disposition: .mapped, detail: "非空时作为 text"),
        MMFieldRow(field: "richcontent NODE plain", disposition: .mapped, detail: "TEXT 为空时作为 text；两边都有且不同时写入 note"),
        MMFieldRow(field: "richcontent NOTE plain", disposition: .mapped, detail: "note；多个 NOTE 时模型留下最后一段纯文本"),
        MMFieldRow(field: "richcontent markup", disposition: .passthrough, detail: "映射出的纯文本没变时原样写回；NOTE 纯文本变了就重写 NOTE；NODE 富文本在文字变了、或它曾被折进 note 且 note 变了时丢掉"),
        MMFieldRow(field: "richcontent DETAILS", disposition: .passthrough, detail: "不进 note，整段写回"),
        MMFieldRow(field: "LINK", disposition: .mapped, detail: "link"),
        MMFieldRow(field: "FOLDED", disposition: .mapped, detail: "isCollapsed；只有 true 算折叠"),
        MMFieldRow(field: "POSITION left/right", disposition: .mapped, detail: "side"),
        MMFieldRow(field: "POSITION other", disposition: .gap, detail: "导入报 unknownPosition，不猜"),
        MMFieldRow(field: "ID", disposition: .mapped, detail: "ID_ 加 32 位十六进制复用为 UUID；其他字符串写回，模型另用新 UUID"),
        MMFieldRow(field: "CREATED MODIFIED", disposition: .passthrough, detail: "不是文档的 createdAt / modifiedAt"),
        MMFieldRow(field: "color attributes", disposition: .passthrough, detail: "COLOR、BACKGROUND_COLOR、STYLE 不进 MindMapNodeStyle"),
        MMFieldRow(field: "icon font edge cloud attribute hook arrowlink encrypted_content", disposition: .passthrough, detail: "元素写回，不变成节点；arrowlink 不是 TopicRelationship"),
        MMFieldRow(field: "children order", disposition: .mapped, detail: "children 顺序"),
        MMFieldRow(field: "free position", disposition: .gap, detail: ".mm 没有 x/y"),
        MMFieldRow(field: "freeNodes", disposition: .gap, detail: "不写进 .mm"),
        MMFieldRow(field: "stickies", disposition: .gap, detail: "便签不是主题"),
        MMFieldRow(field: "regions", disposition: .gap, detail: "专区不是主题"),
        MMFieldRow(field: "model style", disposition: .gap, detail: "Floretta 自己的样式不写进本来没有这些属性的 .mm"),
        MMFieldRow(field: "relationships", disposition: .gap, detail: "不写成 TopicRelationship；arrowlink 仍按元素写回"),
        MMFieldRow(field: "multiple roots", disposition: .gap, detail: "导出多个根时用文档标题包一层；文件里已有的多个根在映射没变时按原字节写回"),
        MMFieldRow(field: "comments and doctype", disposition: .gap, detail: "未改映射时留在原字节里；改过之后不重写"),
        MMFieldRow(field: "external entity", disposition: .gap, detail: "拒绝解析"),
    ]
}
