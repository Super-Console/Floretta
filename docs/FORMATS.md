# 格式支持矩阵

> 原则：**先能导入，再谈导出；先能读真实样本，再声称"支持"。**
> 每个格式必须用真实文件往返验证，并把结果填进本文件末尾的验收表。

## 分级

### A 级 — 本期必做（P2）

| 格式 | 归属 | 实际形态 | 读 | 写 |
|---|---|---|---|---|
| `.supernode` | 本项目 | JSON（UTF-8） | ✅ | ✅ |
| `.mm` | FreeMind / Freeplane | XML | ✅ | ✅ |
| `.opml` | 通用大纲格式（OmniOutliner、多数导图工具） | XML | ✅ | ✅ |
| Markdown | 通用纯文本 | 缩进列表 / 标题层级 | ✅ | ✅ |
| PNG / PDF | 图片输出 | — | ❌ | ✅ |

选 `.mm` 的理由：它是开源导图生态的事实互换格式，Freeplane、FreeMind、多数阅读器都能读；
文本 + 折叠 + 备注都能表达，做起来比 XMind 干净。

### B 级 — 二期导入优先

| 格式 | 归属 | 形态（已核实的部分） | 说明 |
|---|---|---|---|
| `.xmind` | Xmind Ltd. | ZIP，内含 `content.json`（旧版可能是 `content.xml`） | 双向读写 `content.json`。映射字段见 `docs/XMIND-FIELDS.md`；读不懂的键和 zip 条目 pass-through。只有 `content.xml` 的 XMind 8 文件不导入。 |
| `.itmz` | iThoughts (toketaWare) | ZIP + XML + 附件 | 作者本人称格式"相对开放"；需真实样本验证 |
| `.mmap` | MindManager | ZIP + `Document.xml` + 资源 | 内容含大量二进制/专有结构，只做尽力导入 |
| `.smmx` | SimpleMind | XML | 待用样本核实结构 |
| `.wxml` | WiseMapping | XML（对方 README 列出 `.wxml/.mm/.mmx/.xmind/.mmap` 互导） | 待核实 |

### C 级 — 明确不做（先记录，别偷偷做）

- `.mindnode`：MindNode 在 2025.4 起调整了自有文件格式（新增 "MindNode Next" 文档导出）。
  结构需实测；且属闭源厂商私有格式，优先级低。
- `.pos`（ProcessOn）：本质是 JSON，但只有 ProcessOn 自家能完整还原。需要时单独做一次性转换工具，
  不进主线。
- 加密/带密码的导图文件：不解析。

## 硬规矩

1. **导入失败必须明确报错**，不许"尽量猜"出一个半成品导图然后悄悄丢节点。
2. **导出要说清楚丢了什么**：例如 `.mm` 里表达不了自由布局坐标，就要在导出选项里提示。
3. **不许把"能解析"说成"兼容"**：兼容 = 对方软件打开后层级、文字、折叠、备注都对。
4. 每个格式一个独立 codec 文件 + 一组往返测试样本（放 `Tests/Fixtures/`）。
5. 第三方格式的商标和格式说明属于各自厂商；只实现兼容读写，不在产品里使用其品牌做背书。

## `.mm` 本批（P2-1）

读写都进同一棵 `MindMapDocument`，不另建树。实现按公开的 FreeMind XML 形状（`map` / `node` / `TEXT` / `richcontent` / `LINK` / `FOLDED` / `POSITION`）自己写，没有复制 Freeplane 源码。

`.mm` 只有一个根 `node`。文档有多个根时，导出用文档标题包一层；再导入会看到那个包装节点。单个根的文件不包、不拆。

布局仍按子树高度分边。`side` 只是记下来的 `POSITION`，这一批不改 `LayoutEngine`。画布上的 `MindMapPoint` 坐标写不进 `.mm`。

### 保留

| `.mm` | 落到 |
|---|---|
| 节点顺序 | `children` 顺序 |
| `TEXT` | `text`（非空时优先） |
| `richcontent TYPE="NODE"` 的纯文本 | `TEXT` 为空时作为 `text`；两边都有且不同时，纯文本写入 `note`（已有备注则换行接上） |
| `richcontent TYPE="NOTE"` 的纯文本 | `note` |
| `LINK` | `link` |
| `FOLDED="true"` | `isCollapsed` |
| `POSITION="left"` / `"right"` | `side` |

HTML 标签去掉，只留文字进模型。`p` / `br` 变成换行。`richcontent` 必须是良构 XML。原来的标记留在 `mmForeign`，映射出的纯文本没变就原样写回。

字段对照见 **[MM-FIELDS.md](./MM-FIELDS.md)**。

### 原样写回

不进模型、但文件里还在的：`ID`（不是本 codec 的 `ID_` + 32 位十六进制时）、`CREATED`、`MODIFIED`、颜色和样式属性，以及 `icon`、`font`、`edge`、`cloud`、`arrowlink`、`attribute`、`hook`、`encrypted_content`、`richcontent` 整段（含 `DETAILS` 和加粗）。用户没改映射字段时，导出是导入的原字节。改了文字或备注之后，这些属性仍写回；变过的备注改写成纯文本 `<p>`。

`ID_` + 32 位十六进制复用为节点 UUID，所以本程序写出的文件再导入，节点 id 不变。

### 有意丢掉

- 自由坐标（`.mm` 没有 x/y）
- 自由节点（`freeNodes`）。写进 `.mm` 会变成树里的子主题，所以不写
- 便签（`stickies`）。不是主题，不写进 `.mm`
- Floretta 自己的 `MindMapNodeStyle`、关系线。文件里原来就有的颜色和图标写回，不会把模型样式发明进一个本来没有它们的 `.mm`
- 未知的 `POSITION` 值：导入直接报错，不猜
- 注释和 DOCTYPE：映射没变时留在原字节里；改过映射之后不重写

`.opml` 与 Markdown 见下一节。PNG / PDF 见再下一节。

## `.opml` 本批

公开 OPML 2.0：`opml` / `head` / `title` / `body` / 嵌套 `outline`。同一棵 `MindMapDocument`。没有第三方库。

多个顶层 `outline` 就是多个根，不再包一层。

### 保留

| OPML | 落到 |
|---|---|
| 嵌套与顺序 | `children` 顺序 |
| `text` | `text`（非空时优先） |
| `title` | `text` 为空时作为标题；两边都有且不同时写入 `note` |
| `_note` | `note`（优先） |
| `note` | `_note` 没有时作为 `note`；两边都有且不同则换行接上 |
| `url` | `link` |
| `head/title` | 文档 `title` |

导出：映射没变时写回原字节。这一项的 `text` / `note` / `link` 没变时，`title` 和 `note` 属性按读入时的样子留下。变了就写 `text`、`_note`、`url`，并保留不认识的属性。

字段对照见 **[OPML-FIELDS.md](./OPML-FIELDS.md)**。

### 原样写回

`head` 里除标题外的元素（`expansionState`、`ownerName`、日期），以及 `outline` 上未映射的属性（`type`、`xmlUrl`、`htmlUrl`、`description`、`category`）和非 `outline` 子元素（例如 `hook`）。它们不变成节点。用户没改映射字段时，导出是导入的原字节。

### 导入默认（OPML 没有这些字段）

| 模型 | 导入值 |
|---|---|
| `isCollapsed` | `false` |
| `side` | 空 |
| `position`（画布坐标） | 空 |

导出时折叠和左右侧不写回，再导入会回到上表。这是格式缺口，不是静默丢掉正文。

### 有意丢掉

- 折叠、左右侧、画布坐标、自由节点、便签、关系线、样式。OPML 没有这些字段，导出不发明
- 节点 id。每次导入新的 UUID
- 注释和 DOCTYPE：映射没变时留在原字节里；改过映射之后不重写
- `head/title` 内部的标签：改过映射之后只写纯文本标题

外部实体拒绝解析。

## Markdown 一等文档（`.md`）

`.md` 是与 `.floretta` 并列的一等文档投影（可直接打开 / 编辑 / 保存），**不是**「仅导出」格式。

完整规则、双向映射、失败语义、UI 验收合同与分期见 **[MD-AS-DOCUMENT.md](./MD-AS-DOCUMENT.md)**（Censor 已通过）。

摘要硬边界：

- 主层级：嵌套列表（写出只 `- ` + 2 空格缩进）；标题仅可选 **一级**（`# `）分区；列表外 `##`+ 打开失败。
- 可选：备注（`>`）、YAML front-matter 原样保留、整项恰好一个行内链接。
- **不保真**：不写附件、颜色、关系线、位置、折叠、节点 UUID、自由节点、便签；禁止 sidecar / HTML 注释藏数据。自由节点不是列表子项。便签也不是。
- 旧「纯标题树」导出仍是「导出为…」里的可选预设，与打开/保存 `.md` 文档路径分离。导入把标题和列表读成同一棵层级，写出仍只有标题深度；认不出的行失败，不把多余内容原样留下。

字段对照见 **[MARKDOWN-FIELDS.md](./MARKDOWN-FIELDS.md)**。文档 codec 这一轮没有改写；上表的不保真是规格，不是漏映射。

AI 路径定位见 **[FORMAT-FOR-AI.md](./FORMAT-FOR-AI.md)**。

## `.xmind` 双向读写

ZIP 内的 `content.json` 可以导入再导出。字段对照表在 **[XMIND-FIELDS.md](./XMIND-FIELDS.md)**。样本在 `Tests/FlorettaCoreTests/Fixtures/XMind/`。

第一张画布落在文档的 `title` / `roots` / `freeNodes` / `relationships`。后面的画布落在 `additionalCanvases`。编辑器仍只改第一张；导出时其余画布按导入时的样子写回。

自由节点仍是根主题的 `children.detached`，并带 `position`。嵌套的 detached 不进树，留在 pass-through 里。关系在画布的 `relationships`（`end1Id` = source，`end2Id` = target）。画布上先不画线。

读不懂的 JSON 键留在 `xmindForeign` 的 `source` 上。`content.json` 的原始字节也留着：映射字段没变时，导出就是这串字节。改了一个映射字段之后，用 `source` 做底写出新的 `content.json`，没改的键仍按原值写回。`metadata.json`、`manifest.json`，以及 `resources/`、缩略图和其他条目，按原字节写回。

`xap:` 附件在 zip 里有对应条目时，写成 `NodeAttachment`，字节留在 `xmindForeign.entries`，不复制进 `.floretta` 的 `assets/`。Floretta 自己的附件仍写 `org.floretta.attachments`，字节仍在 `.floretta`。

主题 id 不是 UUID 时，模型里用稳定派生的 UUID，导出写回原来的字符串。只有 `content.xml`、没有 `content.json` 的文件直接失败。便签不是主题，不写进 `.xmind`。

从 Floretta 新建、没有 `xmindForeign` 的文档，导出仍是一张画布。多个根时用文档标题包一层。没有根时同样包一层，避免自由节点被塞进树。

## TextBundle 导出

`.textbundle` 是目录，`.textpack` 是同一批文件的 zip。规格见 <http://textbundle.org/spec/>。只导出，不导入。字段对照在 **[TEXTBUNDLE-FIELDS.md](./TEXTBUNDLE-FIELDS.md)**。样本在 `Tests/FlorettaCoreTests/Fixtures/TextBundle/`。

`text.md` 用 `FlorettaMarkdownDocumentCodec.save`，也就是导图的 Markdown 文档（嵌套列表、可选一级分区、备注、单个链接、front matter）。不走标题深度的 `FlorettaMarkdown`。那个 codec 不写附件。能写成 Markdown 的附件，在节点备注后面加相对路径：图片是 `![...](assets/...)`，其他文件是 `[...](assets/...)`，字节在 `assets/`。

自由节点、其他画布、便签、关系线、样式、坐标、折叠和节点 id 写不进去。没给字节的附件不写坏链接。`info.json` 的 `version` 是 2，`type` 是 `net.daringfireball.markdown`，`creatorIdentifier` 是 `net.timhuang.floretta`。

## PNG / PDF 本批

用系统 `ImageRenderer` 把当前导图画成图。PDF 走 `renderer.render { size, draw in }`，把 SwiftUI 画进 PDF 页。没有自写光栅器，也没有第三方导出库。

画面是节点、连线和（用户打开开关时）便签。不含工具栏、侧栏大纲、点阵、选中蓝框和缩放手柄。范围是这些内容的外接矩形再加固定留白（默认 32pt）。便签默认画进 PNG 和 PDF；设置里的「导出包含便签」可以关掉，关掉后便签仍留在 `.floretta`。

折叠节点的子树不出现，因为导出用的就是布局结果，折叠子节点本来就不在框里。

PNG 可选 2x 或 3x，底可以是白的或透明的。

像素长边默认不超过 8192。再大就从内容左上角裁到这个上限，并带上一句说明：「导出已按最大尺寸裁切，超出的内容没有画进文件。」空白图则说明没有可导出的节点。

## 验收表（执行者填，总指挥核）

| 格式 | 方向 | 样本来源 | 保留项 | 丢失项 | 结论 | 日期 |
|---|---|---|---|---|---|---|
| `.mm` | 导入 + 导出 | `Fixtures/MM/` 与文档往返 | 层级、顺序、TEXT、richcontent 纯文本、NOTE、LINK、FOLDED、POSITION、`ID_`+32hex；其余属性和元素原样写回 | 自由坐标、自由节点、便签、模型样式、关系线；未知 POSITION 报错；注释在改过映射后不重写 | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-10 |
| `.opml` | 导入 + 导出 | `Fixtures/OPML/` 与文档往返 | 层级、顺序、text、title/_note/note、url、文档标题；head 其余元素和未知属性原样写回 | 折叠、左右侧、画布坐标、自由节点、便签、样式、节点 id；注释在改过映射后不重写 | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-10 |
| Markdown | 一等文档读写 + 大纲导入 / 纯标题预设 | 见 MD-AS-DOCUMENT 与 `Fixtures/MarkdownHeading/` | 文档：层级、顺序、text、note、单一 link、front-matter。大纲导入：标题深度、列表缩进、text、note、单一 link | 附件、颜色、关系线、位置、折叠、UUID；文档 `##`+ 拒开；大纲导入认不出的行失败。不把这些补成假保真 | 文档 codec 未改；大纲导入读标题和列表，写出仍是标题。字段表见 MARKDOWN-FIELDS | 2026-11-10 |
| PNG / PDF | 仅导出 | 单测把 PNG 读回并抽样像素；PDF 看页数和 mediaBox | 当前可见节点、连线、概要括号和边界；2x/3x；白底或透明 | 工具栏、侧栏、选中框、点阵；折叠起来的子树；超出像素上限的部分 | 代码与单测已落盘；本机未打开文件 | 2026-11-10 |
| `.xmind` | 导入 + 导出 + 再导入 | `Tests/FlorettaCoreTests/Fixtures/XMind/` 六类样本，加单测里的 `MindMapDocument` | 层级、文字、备注、链接、根上的自由节点、关系线、概要、边界、已映射的样式、xap 附件引用和字节、多画布、主题标签与 markerId；未知字段在未改映射时按原 `content.json` 字节写回 | 折叠不进 `isCollapsed`、嵌套浮动主题不可编辑、XMind 8 仅 `content.xml`、便签；概要不进 children；改映射字段后数字会按 JSON 数字重写。详见 `docs/XMIND-FIELDS.md` | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-10 |
| TextBundle | 仅导出 | `Tests/FlorettaCoreTests/Fixtures/TextBundle/` 的 simple、nested、attachments | 第一张画布的层级、文字、备注、链接、front matter、一级分区；有字节的树上图片和文件，相对路径进 text.md，字节进 assets/ | 不导入。自由节点、其他画布、便签、关系线、样式、坐标、折叠、节点 id、文档标题、缺字节的附件。详见 `docs/TEXTBUNDLE-FIELDS.md` | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-10 |

> 空白 = 未验证。不要预填"通过"。
