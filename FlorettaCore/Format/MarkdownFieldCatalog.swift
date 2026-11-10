import Foundation

public enum MarkdownFieldDisposition: String, Equatable, Sendable {
    case mapped
    case passthrough
    case gap
}

public struct MarkdownFieldRow: Equatable, Sendable {
    public var field: String
    public var disposition: MarkdownFieldDisposition
    public var detail: String

    public init(field: String, disposition: MarkdownFieldDisposition, detail: String) {
        self.field = field
        self.disposition = disposition
        self.detail = detail
    }
}

public struct MarkdownFixtureClass: Equatable, Sendable {
    public var name: String
    public var file: String
    public var detail: String

    public init(name: String, file: String, detail: String) {
        self.name = name
        self.file = file
        self.detail = detail
    }
}

/// Field comparison for Markdown.
/// Document rows are `FlorettaMarkdownDocumentCodec` (open/save `.md`).
/// Heading rows are `FlorettaMarkdown`, the optional 「导出为…」preset.
/// `docs/MARKDOWN-FIELDS.md` mirrors these rows.
/// The document codec's structure-only rules are intentional; this catalog does not widen them.
public enum MarkdownFieldCatalog {
    public static let documentFixtures: [MarkdownFixtureClass] = [
        MarkdownFixtureClass(name: "simple", file: "simple-list.md", detail: "仅嵌套列表"),
        MarkdownFixtureClass(name: "sections", file: "with-sections.md", detail: "仅一级分区"),
        MarkdownFixtureClass(name: "notes", file: "with-notes-links.md", detail: "备注和单一链接"),
        MarkdownFixtureClass(name: "front matter", file: "with-front-matter.md", detail: "YAML 原样写回"),
    ]

    public static let headingFixtures: [MarkdownFixtureClass] = [
        MarkdownFixtureClass(name: "heading simple", file: "simple.md", detail: "一层标题"),
        MarkdownFixtureClass(name: "heading nested", file: "nested.md", detail: "五层标题"),
        MarkdownFixtureClass(name: "heading notes", file: "notes-links.md", detail: "引用备注和整段链接"),
    ]

    public static let rows: [MarkdownFieldRow] = [
        MarkdownFieldRow(field: "document front matter", disposition: .passthrough, detail: "markdownFrontMatter 不透明字符串，保存时写回"),
        MarkdownFieldRow(field: "document H1", disposition: .mapped, detail: "列表外恰好一个 # 是分区根，isMarkdownSectionHeading"),
        MarkdownFieldRow(field: "document H2-H6", disposition: .gap, detail: "列表外的 ## 到 ###### 打开失败，报错含行号"),
        MarkdownFieldRow(field: "document list", disposition: .mapped, detail: "读入 - * + 和有序标记；写出只有 - 和 2 空格"),
        MarkdownFieldRow(field: "document list marker", disposition: .gap, detail: "原来的 * + 或序号不写回"),
        MarkdownFieldRow(field: "document tab", disposition: .gap, detail: "Tab 按 2 空格规范化，不写回"),
        MarkdownFieldRow(field: "document text", disposition: .mapped, detail: "列表项或分区标题的 text"),
        MarkdownFieldRow(field: "document single link", disposition: .mapped, detail: "整项恰好一个 [text](url) 时写入 link"),
        MarkdownFieldRow(field: "document multiple links", disposition: .gap, detail: "不止一个链接时整项留在 text，不拆 link"),
        MarkdownFieldRow(field: "document note", disposition: .mapped, detail: "紧随的 > 块是 note"),
        MarkdownFieldRow(field: "document empty item", disposition: .mapped, detail: "显式空列表项保留 text 为空"),
        MarkdownFieldRow(field: "document HTML comment", disposition: .gap, detail: "注释丢掉，禁止拿来藏字段"),
        MarkdownFieldRow(field: "document id", disposition: .gap, detail: "不写 UUID"),
        MarkdownFieldRow(field: "document attachments", disposition: .gap, detail: "不写"),
        MarkdownFieldRow(field: "document style", disposition: .gap, detail: "不写颜色和样式"),
        MarkdownFieldRow(field: "document relationships", disposition: .gap, detail: "不写"),
        MarkdownFieldRow(field: "document position side collapse", disposition: .gap, detail: "打开时用模型默认值，保存时丢掉"),
        MarkdownFieldRow(field: "document freeNodes", disposition: .gap, detail: "自由节点不是列表子项"),
        MarkdownFieldRow(field: "document stickies", disposition: .gap, detail: "便签不是列表子项"),
        MarkdownFieldRow(field: "document unrecognized line", disposition: .gap, detail: "认不出的行打开失败，不猜"),
        MarkdownFieldRow(field: "heading depth", disposition: .mapped, detail: "标题层级是树深；写出 # 的个数等于深度"),
        MarkdownFieldRow(field: "heading text", disposition: .mapped, detail: "标题文字是 text"),
        MarkdownFieldRow(field: "heading note", disposition: .mapped, detail: "> 引用是 note"),
        MarkdownFieldRow(field: "heading single link", disposition: .mapped, detail: "整段标题恰好一个 [text](url) 时写入 link"),
        MarkdownFieldRow(field: "heading unsupported line", disposition: .gap, detail: "不是标题也不是引用就失败，不把多余行原样留下"),
        MarkdownFieldRow(field: "heading front matter", disposition: .gap, detail: "纯标题预设不读 front matter；那是文档 codec 的事"),
        MarkdownFieldRow(field: "heading id style position", disposition: .gap, detail: "不写 UUID、颜色、坐标、左右侧、折叠"),
        MarkdownFieldRow(field: "heading freeNodes", disposition: .gap, detail: "自由节点不写"),
        MarkdownFieldRow(field: "heading stickies", disposition: .gap, detail: "便签不写"),
        MarkdownFieldRow(field: "heading document title", disposition: .gap, detail: "单个根的标题就是根文字；多个根没有单独的文档标题"),
        MarkdownFieldRow(field: "heading newline in text", disposition: .gap, detail: "标题里的换行写成空格"),
    ]
}
