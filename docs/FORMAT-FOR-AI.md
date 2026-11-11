# Floretta 容器与 AI 读写规范

本文以 `FlorettaCore` 当前 Codable 定义及容器实现为准。`.floretta` 正式文件是 ZIP；旧版纯 JSON `.floretta` 只读，不可覆盖保存。

## 容器

ZIP 必须包含：

- `document.json`：`MindMapDocument` 的 UTF-8 JSON。
- `metadata.json`：容器元数据 JSON。
- `assets/<sha256>.<ext>`：附件原字节；SHA-256 为内容的小写 64 位十六进制摘要，扩展名规范化为小写字母/数字、最多 8 字符，无效或空扩展名变成 `bin`。同一摘要只存一份。

每个节点的 `attachments` 元素记录 `sha256`、`fileExtension`、`byteCount`、`filename`；实际字节不放在 JSON 中。资产名的摘要必须匹配其字节，缺引用资产、坏摘要或坏资产名都会导致读取失败。不要重编码或转码附件。ZIP 中除上述项目外的额外条目当前不会作为通用未知条目保留；不要在编辑时依赖它们。

`metadata.json` 五个字段均必需：`containerVersion`（integer，只接受 `1`）、`createdAt` 和 `modifiedAt`（UTC ISO-8601 string）、`appVersion`（string，程序新建包默认 `"1.0"`）、`defaultView`（string，程序新建包默认 `"canvas"`）。解码不对后两个字符串作枚举约束。元数据时间通常与文档时间一致，但编码独立存储，读写器应保留读入值，不要用当前时间覆盖。

## `document.json` 字段

顶层必须字段缺失、类型不符或版本不支持时，解码失败。JSON 数值使用整数/浮点数，UUID 使用标准 UUID 字符串，时间戳使用 UTC ISO-8601（秒或带小数秒）。

| JSON 字段 | 类型 | 必需 | 缺省/含义 |
|---|---|---:|---|
| `formatVersion` | integer | 是 | 只接受 `1`；不可擅自升级。 |
| `title` | string | 是 | 文档标题。 |
| `createdAt` | string（UTC ISO-8601） | 是 | 创建时间。 |
| `modifiedAt` | string（UTC ISO-8601） | 是 | 修改时间。 |
| `roots` | node[] | 是 | 主画布有序树根；可以为空。 |
| `freeNodes` | node[] | 否 | 主画布自由节点，不参与树布局；缺省 `[]`，空数组省略。 |
| `relationships` | relationship[] | 否 | 主画布节点连接；缺省 `[]`，空数组省略。 |
| `stickies` | sticky[] | 否 | 主画布便签；缺省 `[]`，空数组省略。 |
| `regions` | region[] | 否 | 主画布专区；缺省 `[]`，空数组省略。 |
| `markdownFrontMatter` | string 或 null | 否 | Markdown 投影的原始 YAML front matter；缺省/null 省略。 |
| `additionalCanvases` | canvas[] | 否 | 第二张及后续画布；缺省 `[]`，空数组省略。 |
| `xmindForeign` | object 或 null | 否 | XMind 来源数据/未知键保留袋；缺省/null 省略。 |
| `opmlForeign` | object 或 null | 否 | OPML 来源数据/未映射内容保留袋；缺省/null 省略。 |
| `mmForeign` | object 或 null | 否 | FreeMind 来源数据/未映射内容保留袋；缺省/null 省略。 |
| `themeID` | string 或 null | 否 | 主题预设 ID；无有效值表示标准主题，缺省/null 省略。 |
| `activeCanvasIndex` | integer | 否 | 当前画布，0 为主画布；缺省 `0`，越界读取回落到 0，0 省略。 |
| `primaryCanvasTitle` | string 或 null | 否 | 主画布独立标题；缺省/null 省略，空白标题读取时清空。 |
| `primaryCanvasViewport` | viewport object | 否 | 主画布缩放和平移；缺省为标准相机，标准相机省略。 |

### 节点 `MindMapNode`

字段名 `collapsed` 对应 Swift 属性 `isCollapsed`。

| JSON 字段 | 类型 | 必需 | 缺省/含义 |
|---|---|---:|---|
| `id` | UUID string | 是 | 稳定节点身份。 |
| `text` | string | 是 | 节点正文。 |
| `note` | string | 是 | 备注；无备注也要写 `""`。 |
| `collapsed` | boolean | 是 | 折叠状态；无折叠也要写 `false`。 |
| `style` | style object 或 null | 否 | 样式覆盖；缺省/null 省略。 |
| `position` | `{ "x": number, "y": number }` 或 null | 否 | 画布位置；缺省/null 省略。 |
| `link` | string 或 null | 否 | 链接；缺省/null 省略。 |
| `side` | `"left"` / `"right"` 或 null | 否 | FreeMind 分支侧；缺省/null 省略。 |
| `attachments` | attachment[] | 否 | 附件引用；缺省 `[]`，空数组省略。 |
| `children` | node[] | 是 | 按显示顺序排列的子节点；无子节点也写 `[]`。 |
| `isMarkdownSectionHeading` | boolean | 否 | 是否为 Markdown 一级分区标题；缺省 `false`，false 省略。 |
| `summaries` | summary[] | 否 | 覆盖连续子节点范围的概要记录，不是 children；缺省 `[]`，空数组省略。 |
| `boundaries` | boundary[] | 否 | 包围连续子节点的区域标记，不是 children；缺省 `[]`，空数组省略。 |
| `labels` | string[] | 否 | 标签；缺省 `[]`，空数组省略。 |
| `markers` | marker[] | 否 | XMind marker；缺省 `[]`，空数组省略。 |

`style` 必需 `colorHex: string`；`fillHex`、`borderHex`、`textHex`、`fontDesign`、`fillStyle`、`borderStyle` 是可选 string；`fontSize`、`borderWidth`、`topicWidth`、`cornerRadius` 是可选 number；`bold`、`italic`、`strikethrough`、`underline` 是可选 boolean。未设置的可选键省略。

`attachment` 必需：`sha256: string`、`fileExtension: string`、`byteCount: integer`、`filename: string`。`summary` 必需 `id: UUID string`、`text: string`、`rangeStart: integer`、`rangeEnd: integer`；`boundary` 必需 `id`、`title: string`、`rangeStart`、`rangeEnd`。范围是包含首尾的 `children` 下标，必须满足 `0 <= rangeStart <= rangeEnd < children.count`。

### 其他嵌套对象

- `relationship`：必需 `id`、`sourceID`、`targetID`（UUID string）；`title: string` 可选，缺省 `""` 且空值省略。两端必须指向同一画布现存 topic。
- `sticky`：必需 `id`（UUID）、`text`（string）、`color`（`yellow|pink|green|blue|orange`）、`origin`（point）、`width`、`height`（number）。宽高缺省值仅在程序创建时分别为 176、132；JSON 解码要求字段存在，读取会按限制夹取。
- `region`：必需 `id`（UUID）、`origin`（point）、`width`、`height`（number）；`label` 可缺省 `""`，`aspectLocked` 缺省 false，`shape` 缺省 `rectangle`（或 `ellipse`），`fill`/`border` 缺省标准颜色，`strokeWidth` 缺省 2。编码器会写出所有这些字段；尺寸和描边宽度会被夹取。
- `canvas`：必需 `id`（UUID string）、`title`（string）、`roots`（node[]）；`freeNodes`、`relationships`、`stickies`、`regions` 缺省均是 `[]`，空便签/专区数组写出时省略；`viewport` 缺省是标准相机。不得只复制树而丢失其余字段。
- `viewport`：必需 number `scale`、`offsetX`、`offsetY`；标准状态 `{ "scale": 1, "offsetX": 0, "offsetY": 0 }` 在所属字段中省略。不要删除非标准状态。
- `point`：必需 number `x`、`y`。
- `marker`：保留完整对象及其原始字段；marker 形状见 `FlorettaCore/Model/TopicTags.swift`。

## ID 稳定性与地址

`.floretta` 使用 UUID 作为节点 ID。编辑 text、note、link、样式、折叠、附件、插入/删除兄弟、重排或移动现存节点时，现存节点 UUID 必须不变；插入新节点时分配新 UUID；删除节点时只删除该节点及被删除子树的 ID。复制节点/画布时，副本必须生成全新的、全局不冲突的 UUID，并同步更新内部引用。概要、边界、关系、便签、专区及画布也各有 ID，不能与其他对象重复。

Markdown AI 地址是 `root` 路径，不是 UUID。下标从 0 开始，顺序取 JSON 数组当前顺序：`root/3/1` 表示 `roots[3].children[1]`。`root` 指整片 `roots` 森林，不是节点；传给节点读取/编辑会报错。自由节点、便签、专区、其他画布均不在此路径空间。越界、空路径分段、负数、正号、前导零均无效；只有整个字符串首尾允许空白。路径在插入、删除或移动后可能改变，必须基于新树重算。路径解析只验证语法，是否存在由树查找另行验证。

移动节点会改变其 Markdown 路径，但不改变 `.floretta` UUID。普通修改和同一文档内重排不改 ID。OPML 导入会为节点创建新 UUID；不要把跨格式导入视为 ID 稳定。

## 未知字段与保真边界

**能安全忽略**：纯展示/缓存派生值、当前编辑器选择、未落盘的运行时状态；这些不是 `document.json` 持久化字段。

**必须保留**：所有已知字段（包括当前不编辑的 `freeNodes`、多画布、视口、附件引用、labels/markers、relationships、stickies、regions、summaries、boundaries、theme 与各 foreign 字段），其 ID 和数组顺序；另须保留附件原字节及外部格式 foreign bags。不得将不熟悉的已知字段删掉或重置成默认值。

重要实现限制：Swift Codable 会忽略 schema 以外的普通 JSON 键，但不会将这些任意键保存回 `MindMapDocument`；只有显式 foreign 字段用于保存对应格式的原始/未知数据。因此外部编辑器若要无损往返未知键，必须在 JSON 层保留未知键并合并写回，不能只 decode 后重新 encode Core 模型。未知 ZIP 条目也不保证保留。不要宣称当前 Core 会自动做到任意未知字段原样保留。

## 可直接用于测试的 JSON

最小合法 `document.json`（固定 ID 便于断言）：

```json
{
  "formatVersion": 1,
  "title": "Example",
  "createdAt": "2026-01-01T00:00:00Z",
  "modifiedAt": "2026-01-01T00:00:00Z",
  "roots": [
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "text": "中心",
      "note": "",
      "collapsed": false,
      "children": []
    }
  ]
}
```

带附件的合法节点引用示例：`hello` 的 UTF-8 字节 SHA-256 是 `2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824`。在上例根节点内增加 `attachments`，并在 ZIP 增加 `assets/2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824.txt`，其字节严格为 `hello`：

```json
"attachments": [
  {
    "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
    "fileExtension": "txt",
    "byteCount": 5,
    "filename": "hello.txt"
  }
]
```

此附件对象必须放在含 `id/text/note/collapsed/children` 的节点对象中。完整测试可用 `ZipContainer` 写入 `FlorettaPackage(document:..., assets: [FlorettaAsset(sha256:..., fileExtension: "txt", data: Data("hello".utf8))])`，再读回验证文档与字节。

## 依据

`FlorettaCore/Model/MindMapDocument.swift`、`MindMapNode.swift`、`CanvasSheets.swift`、`StickyNote.swift`、`CanvasRegion.swift`、`TopicSummary.swift`、`TopicTags.swift`、`Attachments/AttachmentPolicy.swift`、`Container/DocumentContainer.swift`、`Container/ZipContainer.swift`、`AI/FlorettaNodePath.swift`。
