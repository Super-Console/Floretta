import Foundation

public enum XMindFieldDisposition: String, Equatable, Sendable {
    case mapped
    case passthrough
    case gap
}

public struct XMindFieldRow: Equatable, Sendable {
    public var field: String
    public var disposition: XMindFieldDisposition
    public var detail: String

    public init(field: String, disposition: XMindFieldDisposition, detail: String) {
        self.field = field
        self.disposition = disposition
        self.detail = detail
    }
}

public struct XMindFixtureClass: Equatable, Sendable {
    public var name: String
    public var file: String
    public var detail: String

    public init(name: String, file: String, detail: String) {
        self.name = name
        self.file = file
        self.detail = detail
    }
}

/// Field comparison for `.xmind`. `docs/XMIND-FIELDS.md` mirrors these rows.
public enum XMindFieldCatalog {
    public static let fixtures: [XMindFixtureClass] = [
        XMindFixtureClass(name: "simple", file: "simple.xmind", detail: "单根、一个子主题、备注、链接、未知标签"),
        XMindFixtureClass(name: "nested", file: "nested.xmind", detail: "五层主题，外加 summary 与 structureClass"),
        XMindFixtureClass(name: "styled", file: "styled.xmind", detail: "主题样式映射，shape-class 原样留着"),
        XMindFixtureClass(name: "relationships", file: "relationships.xmind", detail: "关系线端点与标题，controlPoints 原样留着"),
        XMindFixtureClass(name: "attachments", file: "attachments.xmind", detail: "xap 附件字节，image 对象原样留着"),
        XMindFixtureClass(name: "multi-sheet", file: "multi-sheet.xmind", detail: "两张画布，第二张进 additionalCanvases"),
    ]

    public static let rows: [XMindFieldRow] = [
        XMindFieldRow(field: "metadata.json", disposition: .passthrough, detail: "原字节写回，改了映射字段也写回"),
        XMindFieldRow(field: "manifest.json", disposition: .passthrough, detail: "条目集合不变时原字节写回"),
        XMindFieldRow(field: "zip entries", disposition: .passthrough, detail: "resources、缩略图和其他非 content 条目按原字节写回"),
        XMindFieldRow(field: "content.xml", disposition: .gap, detail: "只有 XMind 8 的 content.xml、没有 content.json 时导入失败"),
        XMindFieldRow(field: "sheet.id", disposition: .mapped, detail: "UUID 照用；否则稳定派生 UUID，导出写原字符串"),
        XMindFieldRow(field: "sheet.class", disposition: .mapped, detail: "固定为 sheet"),
        XMindFieldRow(field: "sheet.title", disposition: .mapped, detail: "第一张画布是文档标题，其余是 MindMapCanvas.title"),
        XMindFieldRow(field: "sheet.rootTopic", disposition: .mapped, detail: "第一张画布的 roots[0]，其余画布同理"),
        XMindFieldRow(field: "sheet.relationships", disposition: .mapped, detail: "TopicRelationship，端点必须在同一张画布"),
        XMindFieldRow(field: "sheet.topicPositioning", disposition: .passthrough, detail: "不覆盖导入文件里的原值"),
        XMindFieldRow(field: "sheet.theme", disposition: .passthrough, detail: "不解释、不套用"),
        XMindFieldRow(field: "sheet.legend", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "sheet.topicOverlapping", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "sheet.revisionId", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "additional sheets", disposition: .mapped, detail: "MindMapDocument.additionalCanvases，编辑器仍只改第一张"),
        XMindFieldRow(field: "topic.id", disposition: .mapped, detail: "UUID 照用；其他字符串稳定派生，导出写原字符串"),
        XMindFieldRow(field: "topic.class", disposition: .mapped, detail: "固定为 topic"),
        XMindFieldRow(field: "topic.title", disposition: .mapped, detail: "text"),
        XMindFieldRow(field: "topic.children.attached", disposition: .mapped, detail: "children，顺序保持"),
        XMindFieldRow(field: "topic.children.detached", disposition: .mapped, detail: "只在根主题上映射为 freeNodes"),
        XMindFieldRow(field: "topic.children.detached nested", disposition: .passthrough, detail: "嵌套浮动主题不进树，留在 source 里写回"),
        XMindFieldRow(field: "topic.children.summary", disposition: .mapped, detail: "父主题上的 TopicSummary，不进 children"),
        XMindFieldRow(field: "topic.position", disposition: .mapped, detail: "MindMapPoint；根上的 detached 缺坐标时导入为 0,0"),
        XMindFieldRow(field: "topic.notes.plain.content", disposition: .mapped, detail: "note"),
        XMindFieldRow(field: "topic.notes other", disposition: .passthrough, detail: "realHTML 和其他 notes 键"),
        XMindFieldRow(field: "topic.href web", disposition: .mapped, detail: "http、https、mailto 写入 link"),
        XMindFieldRow(field: "topic.href xap", disposition: .mapped, detail: "对应 zip 条目写成 NodeAttachment，href 在导出时写回"),
        XMindFieldRow(field: "topic.labels", disposition: .passthrough, detail: "没有标签模型字段"),
        XMindFieldRow(field: "topic.markers", disposition: .passthrough, detail: "没有标记模型字段"),
        XMindFieldRow(field: "topic.image", disposition: .passthrough, detail: "图片对象不进附件槽，zip 字节仍写回"),
        XMindFieldRow(field: "topic.branch", disposition: .passthrough, detail: "不映射到 isCollapsed"),
        XMindFieldRow(field: "topic.structureClass", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "topic.customWidth", disposition: .passthrough, detail: "不映射到 topicWidth"),
        XMindFieldRow(field: "topic.numbering", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "topic.boundaries", disposition: .mapped, detail: "父主题上的 TopicBoundary"),
        XMindFieldRow(field: "topic.summaries", disposition: .mapped, detail: "range 与 topicId 对应 TopicSummary"),
        XMindFieldRow(field: "topic.extensions floretta", disposition: .mapped, detail: "provider org.floretta.attachments 写入 NodeAttachment"),
        XMindFieldRow(field: "topic.extensions other", disposition: .passthrough, detail: "其他 provider 原样留着"),
        XMindFieldRow(field: "topic.style.id", disposition: .passthrough, detail: "样式 id 不解释"),
        XMindFieldRow(field: "topic.style.line-color", disposition: .mapped, detail: "colorHex"),
        XMindFieldRow(field: "topic.style.svg:fill", disposition: .mapped, detail: "fillHex"),
        XMindFieldRow(field: "topic.style.fo:color", disposition: .mapped, detail: "textHex"),
        XMindFieldRow(field: "topic.style.fo:font-family", disposition: .mapped, detail: "fontDesign"),
        XMindFieldRow(field: "topic.style.fo:font-size", disposition: .mapped, detail: "fontSize，去掉 pt/px"),
        XMindFieldRow(field: "topic.style.fo:font-weight", disposition: .mapped, detail: "bold"),
        XMindFieldRow(field: "topic.style.fo:font-style", disposition: .mapped, detail: "italic"),
        XMindFieldRow(field: "topic.style.fo:text-decoration", disposition: .mapped, detail: "underline 与 strikethrough"),
        XMindFieldRow(field: "topic.style.border-line-color", disposition: .mapped, detail: "borderHex"),
        XMindFieldRow(field: "topic.style.border-line-width", disposition: .mapped, detail: "borderWidth"),
        XMindFieldRow(field: "topic.style.border-line-pattern", disposition: .mapped, detail: "borderStyle"),
        XMindFieldRow(field: "topic.style.fill-pattern", disposition: .mapped, detail: "fillStyle"),
        XMindFieldRow(field: "topic.style.shape-class", disposition: .passthrough, detail: "不映射到 cornerRadius"),
        XMindFieldRow(field: "topic.style.line-class", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "topic.style.line-width", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "relationship.id", disposition: .mapped, detail: "TopicRelationship.id"),
        XMindFieldRow(field: "relationship.class", disposition: .mapped, detail: "固定为 relationship"),
        XMindFieldRow(field: "relationship.end1Id", disposition: .mapped, detail: "sourceID"),
        XMindFieldRow(field: "relationship.end2Id", disposition: .mapped, detail: "targetID"),
        XMindFieldRow(field: "relationship.title", disposition: .mapped, detail: "title"),
        XMindFieldRow(field: "relationship.controlPoints", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "relationship.style", disposition: .passthrough, detail: "不解释"),
        XMindFieldRow(field: "isCollapsed", disposition: .gap, detail: "branch 会写回，但不会变成折叠状态"),
        XMindFieldRow(field: "labels model", disposition: .gap, detail: "标签只做 pass-through，没有一等字段"),
        XMindFieldRow(field: "stickies", disposition: .gap, detail: "便签不是主题，不写入 .xmind"),
        XMindFieldRow(field: "one href", disposition: .gap, detail: "一个主题只有一个 href，网页链接和 xap 不能同时留在 href 上"),
    ]
}
