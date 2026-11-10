# `.xmind` 字段对照

导入把能解释的字段写进 `MindMapDocument`。解释不了的键和 zip 条目留在 `xmindForeign`，导出时写回。

## 存在哪

- `contentJSON`：导入时的 `content.json` 原字节。映射字段没变时，导出就是这串字节。
- 每张画布、每个主题、每条关系的 `source`：当时的 JSON 对象。改了一个映射字段之后，用它做底，盖上新值，其余键按原值写回。
- `entries`：`resources/`、缩略图，以及其他不是 `content.json` / `metadata.json` / `manifest.json` 的条目。原字节。
- `metadataJSON` / `manifestJSON`：这两份文件的原字节。改了主题文字也会原样写回。
- 第一张画布在文档的 `title`、`roots`、`freeNodes`、`relationships`。其后的画布在 `additionalCanvases`。

样本在 `Tests/FlorettaCoreTests/Fixtures/XMind/`。`XMindFieldCatalog` 与下表是同一份清单，单测会对照。

## 六类样本

| 类 | 文件 | 覆盖 |
|---|---|---|
| simple | `simple.xmind` | 单根、一个子主题、备注、链接、未知标签 |
| nested | `nested.xmind` | 五层主题，外加 summary 与 structureClass |
| styled | `styled.xmind` | 主题样式映射，shape-class 原样留着 |
| relationships | `relationships.xmind` | 关系线端点与标题，controlPoints 原样留着 |
| attachments | `attachments.xmind` | xap 附件字节，image 对象原样留着 |
| multi-sheet | `multi-sheet.xmind` | 两张画布，第二张进 additionalCanvases |

## 字段

| 字段 | 处理 | 说明 |
|---|---|---|
| `metadata.json` | passthrough | 原字节写回，改了映射字段也写回 |
| `manifest.json` | passthrough | 条目集合不变时原字节写回 |
| `zip entries` | passthrough | resources、缩略图和其他非 content 条目按原字节写回 |
| `content.xml` | gap | 只有 XMind 8 的 content.xml、没有 content.json 时导入失败 |
| `sheet.id` | mapped | UUID 照用；否则稳定派生 UUID，导出写原字符串 |
| `sheet.class` | mapped | 固定为 sheet |
| `sheet.title` | mapped | 第一张画布是文档标题，其余是 MindMapCanvas.title |
| `sheet.rootTopic` | mapped | 第一张画布的 roots[0]，其余画布同理 |
| `sheet.relationships` | mapped | TopicRelationship，端点必须在同一张画布 |
| `sheet.topicPositioning` | passthrough | 不覆盖导入文件里的原值 |
| `sheet.theme` | passthrough | 不解释、不套用 |
| `sheet.legend` | passthrough | 不解释 |
| `sheet.topicOverlapping` | passthrough | 不解释 |
| `sheet.revisionId` | passthrough | 不解释 |
| `additional sheets` | mapped | MindMapDocument.additionalCanvases，编辑器仍只改第一张 |
| `topic.id` | mapped | UUID 照用；其他字符串稳定派生，导出写原字符串 |
| `topic.class` | mapped | 固定为 topic |
| `topic.title` | mapped | text |
| `topic.children.attached` | mapped | children，顺序保持 |
| `topic.children.detached` | mapped | 只在根主题上映射为 freeNodes |
| `topic.children.detached nested` | passthrough | 嵌套浮动主题不进树，留在 source 里写回 |
| `topic.children.summary` | mapped | 父主题上的 TopicSummary，不进 children |
| `topic.position` | mapped | MindMapPoint；根上的 detached 缺坐标时导入为 0,0 |
| `topic.notes.plain.content` | mapped | note |
| `topic.notes other` | passthrough | realHTML 和其他 notes 键 |
| `topic.href web` | mapped | http、https、mailto 写入 link |
| `topic.href xap` | mapped | 对应 zip 条目写成 NodeAttachment，href 在导出时写回 |
| `topic.labels` | mapped | MindMapNode.labels，用户原文，顺序保持 |
| `topic.markers` | mapped | markerId 写入 MindMapNode.markers，优先级、进度、旗帜和其他 id 同一份数组 |
| `topic.image` | passthrough | 图片对象不进附件槽，zip 字节仍写回 |
| `topic.branch` | passthrough | 不映射到 isCollapsed |
| `topic.structureClass` | passthrough | 不解释 |
| `topic.customWidth` | passthrough | 不映射到 topicWidth |
| `topic.numbering` | passthrough | 不解释 |
| `topic.boundaries` | mapped | 父主题上的 TopicBoundary |
| `topic.summaries` | mapped | range 与 topicId 对应 TopicSummary |
| `topic.extensions floretta` | mapped | provider org.floretta.attachments 写入 NodeAttachment |
| `topic.extensions other` | passthrough | 其他 provider 原样留着 |
| `topic.style.id` | passthrough | 样式 id 不解释 |
| `topic.style.line-color` | mapped | colorHex |
| `topic.style.svg:fill` | mapped | fillHex |
| `topic.style.fo:color` | mapped | textHex |
| `topic.style.fo:font-family` | mapped | fontDesign |
| `topic.style.fo:font-size` | mapped | fontSize，去掉 pt/px |
| `topic.style.fo:font-weight` | mapped | bold |
| `topic.style.fo:font-style` | mapped | italic |
| `topic.style.fo:text-decoration` | mapped | underline 与 strikethrough |
| `topic.style.border-line-color` | mapped | borderHex |
| `topic.style.border-line-width` | mapped | borderWidth |
| `topic.style.border-line-pattern` | mapped | borderStyle |
| `topic.style.fill-pattern` | mapped | fillStyle |
| `topic.style.shape-class` | passthrough | 不映射到 cornerRadius |
| `topic.style.line-class` | passthrough | 不解释 |
| `topic.style.line-width` | passthrough | 不解释 |
| `relationship.id` | mapped | TopicRelationship.id |
| `relationship.class` | mapped | 固定为 relationship |
| `relationship.end1Id` | mapped | sourceID |
| `relationship.end2Id` | mapped | targetID |
| `relationship.title` | mapped | title |
| `relationship.controlPoints` | passthrough | 不解释 |
| `relationship.style` | passthrough | 不解释 |
| `isCollapsed` | gap | branch 会写回，但不会变成折叠状态 |
| `labels model` | mapped | 标签和标记写在主题上，不另建一份标签表 |
| `stickies` | gap | 便签不是主题，不写入 .xmind |
| `regions` | gap | 专区不是主题，不写入 .xmind |
| `one href` | gap | 一个主题只有一个 href，网页链接和 xap 不能同时留在 href 上 |

处理只有三种：`mapped` 进模型并在导出时从模型写出；`passthrough` 不解释，原值写回；`gap` 是已知做不到的地方，不是静默丢掉。

改了映射字段之后，JSON 数字会按数字重写（`1.0` 可能变成 `1`）。没改映射字段时不重写，`content.json` 与导入字节相同。
