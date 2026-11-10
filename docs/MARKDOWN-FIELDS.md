# Markdown 字段对照

两条路径，不要混：

- **文档**是 `FlorettaMarkdownDocumentCodec`：打开 / 保存 `.md`。规则在 [MD-AS-DOCUMENT.md](./MD-AS-DOCUMENT.md)。这一轮没有改这个 codec。结构只到层级、文字、备注、单一链接和 front matter，是定死的边界，不是漏做。
- **纯标题**是 `FlorettaMarkdown`：「导出为…」里的可选预设。写出时主层级是 `#` 的深度。导入同时读标题和列表：列表按缩进挂到当前标题下，没有标题时自己成树；再导出仍是标题，层级、文字、备注和单一链接往返。认不出的行直接失败，不把多余内容原样留下。

两边都不把颜色、附件、关系线、坐标、折叠或 UUID 写进文件。禁止用 HTML 注释或旁路文件假装保真。

样本：文档在 `Tests/FlorettaCoreTests/Fixtures/MarkdownAsDocument/`，纯标题在 `Tests/FlorettaCoreTests/Fixtures/MarkdownHeading/`。`MarkdownFieldCatalog` 与下表是同一份清单，单测会对照。

## 文档样本

| 类 | 文件 | 覆盖 |
|---|---|---|
| simple | `simple-list.md` | 仅嵌套列表 |
| sections | `with-sections.md` | 仅一级分区 |
| notes | `with-notes-links.md` | 备注和单一链接 |
| front matter | `with-front-matter.md` | YAML 原样写回 |

## 纯标题样本

| 类 | 文件 | 覆盖 |
|---|---|---|
| heading simple | `simple.md` | 一层标题 |
| heading nested | `nested.md` | 五层标题 |
| heading notes | `notes-links.md` | 引用备注和整段链接 |

## 字段

| 字段 | 处理 | 说明 |
|---|---|---|
| `document front matter` | passthrough | markdownFrontMatter 不透明字符串，保存时写回 |
| `document H1` | mapped | 列表外恰好一个 # 是分区根，isMarkdownSectionHeading |
| `document H2-H6` | gap | 列表外的 ## 到 ###### 打开失败，报错含行号 |
| `document list` | mapped | 读入 - * + 和有序标记；写出只有 - 和 2 空格 |
| `document list marker` | gap | 原来的 * + 或序号不写回 |
| `document tab` | gap | Tab 按 2 空格规范化，不写回 |
| `document text` | mapped | 列表项或分区标题的 text |
| `document single link` | mapped | 整项恰好一个 [text](url) 时写入 link |
| `document multiple links` | gap | 不止一个链接时整项留在 text，不拆 link |
| `document note` | mapped | 紧随的 > 块是 note |
| `document empty item` | mapped | 显式空列表项保留 text 为空 |
| `document HTML comment` | gap | 注释丢掉，禁止拿来藏字段 |
| `document id` | gap | 不写 UUID |
| `document attachments` | gap | 不写 |
| `document style` | gap | 不写颜色和样式 |
| `document relationships` | gap | 不写 |
| `document position side collapse` | gap | 打开时用模型默认值，保存时丢掉 |
| `document freeNodes` | gap | 自由节点不是列表子项 |
| `document stickies` | gap | 便签不是列表子项 |
| `document unrecognized line` | gap | 认不出的行打开失败，不猜 |
| `heading depth` | mapped | 标题层级是树深；写出 # 的个数等于深度 |
| `heading text` | mapped | 标题文字是 text |
| `heading note` | mapped | > 引用是 note |
| `heading single link` | mapped | 整段标题恰好一个 [text](url) 时写入 link |
| `heading list` | mapped | 标题下或单独的 - * + 与有序标记按缩进成层级；写出仍是标题 |
| `heading list marker` | gap | 原来的列表标记不写回 |
| `heading unsupported line` | gap | 不是标题、列表或引用就失败，不把多余行原样留下 |
| `heading front matter` | gap | 纯标题预设不读 front matter；那是文档 codec 的事 |
| `heading id style position` | gap | 不写 UUID、颜色、坐标、左右侧、折叠 |
| `heading freeNodes` | gap | 自由节点不写 |
| `heading stickies` | gap | 便签不写 |
| `heading document title` | gap | 单个根的标题就是根文字；多个根没有单独的文档标题 |
| `heading newline in text` | gap | 标题里的换行写成空格 |

处理只有三种：`mapped` 进模型并在写出时从模型写出；`passthrough` 不解释，原样写回；`gap` 是规格里明确不做的地方。文档路径唯一的 passthrough 是 YAML front matter。纯标题路径没有 passthrough。
