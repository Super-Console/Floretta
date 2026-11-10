import Foundation

public enum OPMLFieldDisposition: String, Equatable, Sendable {
    case mapped
    case passthrough
    case gap
}

public struct OPMLFieldRow: Equatable, Sendable {
    public var field: String
    public var disposition: OPMLFieldDisposition
    public var detail: String

    public init(field: String, disposition: OPMLFieldDisposition, detail: String) {
        self.field = field
        self.disposition = disposition
        self.detail = detail
    }
}

public struct OPMLFixtureClass: Equatable, Sendable {
    public var name: String
    public var file: String
    public var detail: String

    public init(name: String, file: String, detail: String) {
        self.name = name
        self.file = file
        self.detail = detail
    }
}

/// Field comparison for `.opml`. `docs/OPML-FIELDS.md` mirrors these rows.
public enum OPMLFieldCatalog {
    public static let fixtures: [OPMLFixtureClass] = [
        OPMLFixtureClass(name: "simple", file: "simple.opml", detail: "单根、两个子节点"),
        OPMLFixtureClass(name: "nested", file: "nested.opml", detail: "五层大纲，备注和链接"),
        OPMLFixtureClass(name: "passthrough", file: "passthrough.opml", detail: "head 元数据、未知属性、hook、text 与 title 不同"),
    ]

    public static let rows: [OPMLFieldRow] = [
        OPMLFieldRow(field: "source bytes", disposition: .passthrough, detail: "映射快照没变时，导出就是导入的原字节"),
        OPMLFieldRow(field: "opml attributes", disposition: .passthrough, detail: "version 和其他根属性写回"),
        OPMLFieldRow(field: "head/title", disposition: .mapped, detail: "文档 title；标题空白时用第一个根的文字"),
        OPMLFieldRow(field: "head other", disposition: .passthrough, detail: "expansionState、ownerName、日期等不进模型，写回"),
        OPMLFieldRow(field: "head/title inner markup", disposition: .gap, detail: "标题内部标签只在未改映射时留在原字节里；改过之后只写纯文本标题"),
        OPMLFieldRow(field: "body outlines", disposition: .mapped, detail: "多个顶层 outline 是多个根，不包一层"),
        OPMLFieldRow(field: "outline order", disposition: .mapped, detail: "children 顺序"),
        OPMLFieldRow(field: "outline text", disposition: .mapped, detail: "非空时作为 text"),
        OPMLFieldRow(field: "outline title", disposition: .mapped, detail: "text 为空时作为标题；两边都有且不同时写入 note"),
        OPMLFieldRow(field: "outline _note", disposition: .mapped, detail: "note，优先于 note"),
        OPMLFieldRow(field: "outline note", disposition: .mapped, detail: "_note 没有时作为 note；两边都有且不同则换行接上"),
        OPMLFieldRow(field: "outline url", disposition: .mapped, detail: "link"),
        OPMLFieldRow(field: "outline unknown attributes", disposition: .passthrough, detail: "type、xmlUrl、htmlUrl、description、category 等"),
        OPMLFieldRow(field: "non-outline children", disposition: .passthrough, detail: "hook 等不变成节点，写回"),
        OPMLFieldRow(field: "isCollapsed", disposition: .gap, detail: "OPML 没有折叠；导入为 false，不写回"),
        OPMLFieldRow(field: "side", disposition: .gap, detail: "不写"),
        OPMLFieldRow(field: "position", disposition: .gap, detail: "没有 x/y"),
        OPMLFieldRow(field: "freeNodes", disposition: .gap, detail: "不写进 .opml"),
        OPMLFieldRow(field: "stickies", disposition: .gap, detail: "便签不是大纲节点"),
        OPMLFieldRow(field: "relationships", disposition: .gap, detail: "不写"),
        OPMLFieldRow(field: "style", disposition: .gap, detail: "不映射到 MindMapNodeStyle，导出也不发明样式"),
        OPMLFieldRow(field: "node id", disposition: .gap, detail: "OPML 没有节点 id；每次导入新的 UUID"),
        OPMLFieldRow(field: "comments and doctype", disposition: .gap, detail: "未改映射时留在原字节里；改过之后不重写"),
        OPMLFieldRow(field: "external entity", disposition: .gap, detail: "拒绝解析"),
    ]
}
