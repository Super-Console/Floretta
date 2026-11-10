import Foundation

public enum TextBundleFieldDisposition: String, Equatable, Sendable {
    case mapped
    case gap
}

public struct TextBundleFieldRow: Equatable, Sendable {
    public var field: String
    public var disposition: TextBundleFieldDisposition
    public var detail: String

    public init(field: String, disposition: TextBundleFieldDisposition, detail: String) {
        self.field = field
        self.disposition = disposition
        self.detail = detail
    }
}

public struct TextBundleFixtureClass: Equatable, Sendable {
    public var name: String
    public var directory: String
    public var detail: String

    public init(name: String, directory: String, detail: String) {
        self.name = name
        self.directory = directory
        self.detail = detail
    }
}

/// Field comparison for TextBundle export. `docs/TEXTBUNDLE-FIELDS.md` mirrors these rows.
public enum TextBundleFieldCatalog {
    public static let fixtures: [TextBundleFixtureClass] = [
        TextBundleFixtureClass(
            name: "simple",
            directory: "Fixtures/TextBundle/simple",
            detail: "单根、备注、一个带链接的子节点，没有附件"
        ),
        TextBundleFixtureClass(
            name: "nested",
            directory: "Fixtures/TextBundle/nested",
            detail: "一级分区、front matter、三层列表"
        ),
        TextBundleFixtureClass(
            name: "attachments",
            directory: "Fixtures/TextBundle/attachments",
            detail: "图片、PDF、同一字节两处引用、文件名冲突、缺字节不写"
        ),
    ]

    public static let rows: [TextBundleFieldRow] = [
        TextBundleFieldRow(field: "info.json version", disposition: .mapped, detail: "整数 2"),
        TextBundleFieldRow(field: "info.json type", disposition: .mapped, detail: "net.daringfireball.markdown，对应 text.md"),
        TextBundleFieldRow(field: "info.json transient", disposition: .mapped, detail: "false。这是导出的文件，不是临时交换容器"),
        TextBundleFieldRow(field: "info.json creatorIdentifier", disposition: .mapped, detail: "net.timhuang.floretta"),
        TextBundleFieldRow(field: "info.json creatorURL", disposition: .mapped, detail: "https://github.com/Super-Console/Floretta"),
        TextBundleFieldRow(field: "info.json sourceURL", disposition: .gap, detail: "导出接口没有来源 URL，不写这个键"),
        TextBundleFieldRow(field: "info.json app dictionary", disposition: .gap, detail: "不把写不进 Markdown 的字段塞进应用私有字典"),
        TextBundleFieldRow(field: "text.md", disposition: .mapped, detail: "FlorettaMarkdownDocumentCodec.save 的正文，再插入附件引用"),
        TextBundleFieldRow(field: "text.md hierarchy", disposition: .mapped, detail: "嵌套列表；根上的 isMarkdownSectionHeading 仍是一级标题"),
        TextBundleFieldRow(field: "text.md note", disposition: .mapped, detail: "备注用 >，位置和缩进跟 Markdown 文档一致"),
        TextBundleFieldRow(field: "text.md link", disposition: .mapped, detail: "整项恰好一个链接时写成 [text](url)"),
        TextBundleFieldRow(field: "text.md front matter", disposition: .mapped, detail: "markdownFrontMatter 写在正文前"),
        TextBundleFieldRow(field: "assets image", disposition: .mapped, detail: "图片扩展名写成 ![文件名](assets/...)，字节放进 assets/"),
        TextBundleFieldRow(field: "assets file", disposition: .mapped, detail: "其他文件写成 [文件名](assets/...)，字节放进 assets/"),
        TextBundleFieldRow(field: "assets shared sha256", disposition: .mapped, detail: "同一个 sha256 只复制一份，多处引用同一相对路径"),
        TextBundleFieldRow(field: "assets filename", disposition: .mapped, detail: "磁盘名用文件名最后一段的 ASCII 安全形式；重名且内容不同时加 sha256 前 8 位；否则用 sha256.扩展名"),
        TextBundleFieldRow(field: "assets label", disposition: .mapped, detail: "链接文字用原始文件名的最后一段，方括号按 Markdown 转义"),
        TextBundleFieldRow(field: "assets missing bytes", disposition: .gap, detail: "节点引用了附件但没有字节：不写坏链接，也不造空文件"),
        TextBundleFieldRow(field: "assets orphan bytes", disposition: .gap, detail: "没被当前画布（缺省第一张）的树引用的字节不进 assets"),
        TextBundleFieldRow(field: "freeNodes", disposition: .gap, detail: "Markdown 文档不写自由节点，文字和附件都不出现"),
        TextBundleFieldRow(field: "additionalCanvases", disposition: .gap, detail: "单树导出只写当前画布（activeCanvasIndex，缺省第一张）的 roots。其余画布留在 .floretta"),
        TextBundleFieldRow(field: "stickies", disposition: .gap, detail: "便签不是主题，不写"),
        TextBundleFieldRow(field: "relationships", disposition: .gap, detail: "Markdown 没有关系线"),
        TextBundleFieldRow(field: "style", disposition: .gap, detail: "颜色和样式不写"),
        TextBundleFieldRow(field: "position side", disposition: .gap, detail: "坐标和左右侧不写"),
        TextBundleFieldRow(field: "isCollapsed", disposition: .gap, detail: "折叠状态不写；子树仍按 Markdown 文档全部写出"),
        TextBundleFieldRow(field: "uuid", disposition: .gap, detail: "不写节点 id"),
        TextBundleFieldRow(field: "document title", disposition: .gap, detail: "文档标题不会单独变成一行，除非它本来就是节点文字"),
        TextBundleFieldRow(field: "import", disposition: .gap, detail: "只导出。图片链接不会被 Markdown 文档 codec 读回成附件"),
        TextBundleFieldRow(field: "textpack", disposition: .mapped, detail: "同一批文件打成 zip，扩展名 .textpack。空的 assets 也写一条目录项"),
    ]
}
