# TextBundle 字段对照

导出把 `MindMapDocument` 写成 [TextBundle](http://textbundle.org/spec/)：`.textbundle` 目录，或同一批文件的 `.textpack` zip。不导入。

`text.md` 用 `FlorettaMarkdownDocumentCodec.save`。这是导图的 Markdown 文档：嵌套列表、可选一级分区、备注、单个链接、front matter。不改用 `FlorettaMarkdown` 的标题深度。那是「导出为…」的旧预设，超过六级就不再是标题，也不是打开和保存 `.md` 的路径。

那个 codec 按规格不写附件，这里也不改它。附件引用是 TextBundle 在每条节点备注之后插进去的。图片写 `![文件名](assets/...)`，其他文件写 `[文件名](assets/...)`。列表项里的引用再缩进两格，留在该项下面。一级分区的引用写在第 0 列，夹在标题备注和后面的列表之间。规格要求资源都用 `assets/` 相对路径。

`TextBundleFieldCatalog` 与下表是同一份清单，单测会对照。

## 样本

| 类 | 目录 | 覆盖 |
|---|---|---|
| simple | `Fixtures/TextBundle/simple` | 单根、备注、一个带链接的子节点，没有附件 |
| nested | `Fixtures/TextBundle/nested` | 一级分区、front matter、三层列表 |
| attachments | `Fixtures/TextBundle/attachments` | 图片、PDF、同一字节两处引用、文件名冲突、缺字节不写 |

样本在 `Tests/FlorettaCoreTests/Fixtures/TextBundle/`。simple 和 nested 的 `text.md` 与 Markdown 文档 codec 的输出相同。attachments 在那份输出的节点后面多了附件行，并带上 `assets/` 里的字节。

## 字段

| 字段 | 处理 | 说明 |
|---|---|---|
| `info.json version` | mapped | 整数 2 |
| `info.json type` | mapped | net.daringfireball.markdown，对应 text.md |
| `info.json transient` | mapped | false。这是导出的文件，不是临时交换容器 |
| `info.json creatorIdentifier` | mapped | net.timhuang.floretta |
| `info.json creatorURL` | mapped | https://github.com/Super-Console/Floretta |
| `info.json sourceURL` | gap | 导出接口没有来源 URL，不写这个键 |
| `info.json app dictionary` | gap | 不把写不进 Markdown 的字段塞进应用私有字典 |
| `text.md` | mapped | FlorettaMarkdownDocumentCodec.save 的正文，再插入附件引用 |
| `text.md hierarchy` | mapped | 嵌套列表；根上的 isMarkdownSectionHeading 仍是一级标题 |
| `text.md note` | mapped | 备注用 >，位置和缩进跟 Markdown 文档一致 |
| `text.md link` | mapped | 整项恰好一个链接时写成 [text](url) |
| `text.md front matter` | mapped | markdownFrontMatter 写在正文前 |
| `assets image` | mapped | 图片扩展名写成 ![文件名](assets/...)，字节放进 assets/ |
| `assets file` | mapped | 其他文件写成 [文件名](assets/...)，字节放进 assets/ |
| `assets shared sha256` | mapped | 同一个 sha256 只复制一份，多处引用同一相对路径 |
| `assets filename` | mapped | 磁盘名用文件名最后一段的 ASCII 安全形式；重名且内容不同时加 sha256 前 8 位；否则用 sha256.扩展名 |
| `assets label` | mapped | 链接文字用原始文件名的最后一段，方括号按 Markdown 转义 |
| `assets missing bytes` | gap | 节点引用了附件但没有字节：不写坏链接，也不造空文件 |
| `assets orphan bytes` | gap | 没被第一张画布的树引用的字节不进 assets |
| `freeNodes` | gap | Markdown 文档不写自由节点，文字和附件都不出现 |
| `additionalCanvases` | gap | 只导出第一张画布的 roots |
| `stickies` | gap | 便签不是主题，不写 |
| `regions` | gap | 专区不是主题，不写 |
| `relationships` | gap | Markdown 没有关系线 |
| `style` | gap | 颜色和样式不写 |
| `position side` | gap | 坐标和左右侧不写 |
| `isCollapsed` | gap | 折叠状态不写；子树仍按 Markdown 文档全部写出 |
| `uuid` | gap | 不写节点 id |
| `document title` | gap | 文档标题不会单独变成一行，除非它本来就是节点文字 |
| `import` | gap | 只导出。图片链接不会被 Markdown 文档 codec 读回成附件 |
| `textpack` | mapped | 同一批文件打成 zip，扩展名 .textpack。空的 assets 也写一条目录项 |

处理只有两种：`mapped` 从模型写出；`gap` 是已知做不到的地方，不是静默丢掉。没有 pass-through，因为导出不读入一份已有的 TextBundle。

磁盘文件名只保留 `[A-Za-z0-9._-]`，空格写成 `-`。中文、`..`、以及其他不安全的名字改成 `<sha256>.<扩展名>`。链接文字仍用原始文件名的最后一段，所以 `笔记.png` 会写成 `![笔记.png](assets/<sha256>.png)`。同一个 sha256 给了两份不同字节时，用第一份。

`.textpack` 用现成的 `ZipArchive.write`（存储法，条目按路径排序）。空包也会带一条 `assets/` 目录项。目录形式的 `writeDirectory` 同样总会建出 `assets/` 文件夹。
