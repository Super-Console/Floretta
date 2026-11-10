# `.opml` 字段对照

导入把能解释的字段写进 `MindMapDocument`。解释不了的属性和元素留在 `opmlForeign`，导出时写回。

## 存在哪

- `sourceXML`：导入时的文件原字节。映射字段没变时，导出就是这串字节。
- `residue`：`opml` / `head` / `body` 上的属性，以及 `head` 里除标题外的元素。改了一个映射字段之后，用它做底，盖上新的标题或大纲，其余原样写回。
- `nodes`：每个 `outline` 的全部属性和非 `outline` 子元素。改了这一项的 `text` / `note` / `link` 之后，只覆盖对应属性（`text`、`_note`、`url`），其余属性还在。没改的项按读入时的属性写出。
- 多个顶层 `outline` 仍是多个根，不包一层。

样本在 `Tests/FlorettaCoreTests/Fixtures/OPML/`。`OPMLFieldCatalog` 与下表是同一份清单，单测会对照。

## 三类样本

| 类 | 文件 | 覆盖 |
|---|---|---|
| simple | `simple.opml` | 单根、两个子节点 |
| nested | `nested.opml` | 五层大纲，备注和链接 |
| passthrough | `passthrough.opml` | head 元数据、未知属性、hook、text 与 title 不同 |

## 字段

| 字段 | 处理 | 说明 |
|---|---|---|
| `source bytes` | passthrough | 映射快照没变时，导出就是导入的原字节 |
| `opml attributes` | passthrough | version 和其他根属性写回 |
| `head/title` | mapped | 文档 title；标题空白时用第一个根的文字 |
| `head other` | passthrough | expansionState、ownerName、日期等不进模型，写回 |
| `head/title inner markup` | gap | 标题内部标签只在未改映射时留在原字节里；改过之后只写纯文本标题 |
| `body outlines` | mapped | 多个顶层 outline 是多个根，不包一层 |
| `outline order` | mapped | children 顺序 |
| `outline text` | mapped | 非空时作为 text |
| `outline title` | mapped | text 为空时作为标题；两边都有且不同时写入 note |
| `outline _note` | mapped | note，优先于 note |
| `outline note` | mapped | _note 没有时作为 note；两边都有且不同则换行接上 |
| `outline url` | mapped | link |
| `outline unknown attributes` | passthrough | type、xmlUrl、htmlUrl、description、category 等 |
| `non-outline children` | passthrough | hook 等不变成节点，写回 |
| `isCollapsed` | gap | OPML 没有折叠；导入为 false，不写回 |
| `side` | gap | 不写 |
| `position` | gap | 没有 x/y |
| `freeNodes` | gap | 不写进 .opml |
| `stickies` | gap | 便签不是大纲节点 |
| `relationships` | gap | 不写 |
| `style` | gap | 不映射到 MindMapNodeStyle，导出也不发明样式 |
| `node id` | gap | OPML 没有节点 id；每次导入新的 UUID |
| `comments and doctype` | gap | 未改映射时留在原字节里；改过之后不重写 |
| `external entity` | gap | 拒绝解析 |

处理只有三种：`mapped` 进模型并在导出时从模型写出；`passthrough` 不解释，原值写回；`gap` 是已知做不到的地方，不是静默丢掉正文。

改了映射字段之后，属性顺序按名字排序，空白会重排。没改映射字段时不重写，文件与导入字节相同。把改过的字段改回去之后，再次导出回到导入时的原字节。
