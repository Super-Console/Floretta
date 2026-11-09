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
| `.xmind` | Xmind Ltd. | ZIP，内含 `content.json`（旧版可能是 `content.xml`） | 结构复杂（主题、样式、关系线、附件、画布）。**只承诺导入层级与文字**，样式尽力而为。 |
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
6. 附件（图片、视频、音频及其他文件）的体积和原样字节见 `docs/ATTACHMENTS.md`。不设单文件 100MB、视频 50MB 的上限。

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

HTML 标签去掉，只留文字。`p` / `br` 变成换行。`richcontent` 必须是良构 XML。

### 有意丢掉

不静默：下面这些不进文档，也不在导出时发明。

- `richcontent` 里的字体、颜色、加粗等标记；`TYPE="DETAILS"` 整段
- `icon`、`font`、`edge`、`cloud`、`arrowlink`、`attribute`、`hook`、`encrypted_content`
- 节点上的 `ID`、`CREATED`、`MODIFIED`、颜色和样式属性（导入时新生成 UUID，导出时写新的 `ID_`）
- 自由坐标（`.mm` 没有 x/y）
- 未知的 `POSITION` 值：导入直接报错，不猜

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

导出写 `text`、`_note`、`url`。不再另写 `title` / `note` 属性。

### 导入默认（OPML 没有这些字段）

| 模型 | 导入值 |
|---|---|
| `isCollapsed` | `false` |
| `side` | 空 |
| `position`（画布坐标） | 空 |

导出时折叠和左右侧不写回，再导入会回到上表。这是格式缺口，不是静默丢掉正文。

### 有意丢掉

- `head` 里除标题外的元数据（`expansionState`、日期、`ownerName` 等）
- `outline` 上未列出的属性（`type`、`xmlUrl`、`htmlUrl`、`description`、`category` 等）
- 非 `outline` 的子元素（例如 `hook`）不变成节点

外部实体拒绝解析。

## Markdown 导出（本批不导入）

深度优先，根是一级标题。第 n 层写 n 个 `#`（超过 6 也继续加，用来保住层级）。

- 标题文字里的换行改成空格，避免把一条标题拆成两段。
- 有 `link` 时标题写成 `[文字](url)`。`]` 会转义，URL 里的空格和 `)` 会百分号编码。
- `note` 紧跟在标题后面，每一行一个 `>`。空备注不写。
- 不写折叠、左右侧、画布坐标。

## PNG / PDF 本批

用系统 `ImageRenderer` 把当前导图画成图。PDF 走 `renderer.render { size, draw in }`，把 SwiftUI 画进 PDF 页。没有自写光栅器，也没有第三方导出库。

画面只有节点和连线。不含工具栏、侧栏大纲、点阵、选中蓝框和缩放手柄。范围是节点外接矩形再加固定留白（默认 32pt）。

折叠节点的子树不出现，因为导出用的就是布局结果，折叠子节点本来就不在框里。

PNG 可选 2x 或 3x，底可以是白的或透明的。

像素长边默认不超过 8192。再大就从内容左上角裁到这个上限，并带上一句说明：「导出已按最大尺寸裁切，超出的内容没有画进文件。」空白图则说明没有可导出的节点。

## 验收表（执行者填，总指挥核）

| 格式 | 方向 | 样本来源 | 保留项 | 丢失项 | 结论 | 日期 |
|---|---|---|---|---|---|---|
| `.mm` | 导入 + 导出 | 测试里的 XML 与 `MindMapDocument` 往返 | 层级、顺序、TEXT、richcontent 纯文本、NOTE、LINK、FOLDED、POSITION | 样式、图标、箭头、属性、钩子、DETAILS、自由坐标、原 ID | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-09 |
| `.opml` | 导入 + 导出 | 测试里的 OPML 与文档往返 | 层级、顺序、text、_note/note、url、文档标题 | 折叠、左右侧、画布坐标、head 元数据、未列出的属性 | 代码与单测已落盘；对方软件打开尚未在本机验 | 2026-11-09 |
| Markdown | 仅导出 | 单测里的样例树 | 标题层级、备注引用、链接 | 不导入；不写折叠、侧、坐标 | 代码与单测已落盘 | 2026-11-09 |
| PNG / PDF | 仅导出 | 单测把 PNG 读回并抽样像素；PDF 看页数和 mediaBox | 当前可见节点和连线；2x/3x；白底或透明 | 工具栏、侧栏、选中框、点阵；折叠起来的子树；超出像素上限的部分 | 代码与单测已落盘；本机未打开文件 | 2026-11-09 |
| `.xmind` | 导入 | 待填 | | | | |

> 空白 = 未验证。不要预填"通过"。
