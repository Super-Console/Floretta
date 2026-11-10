# `.mm` 字段对照

导入把能解释的字段写进 `MindMapDocument`。解释不了的属性和元素留在 `mmForeign`，导出时写回。

## 存在哪

- `sourceXML`：导入时的文件原字节。映射字段没变时，导出就是这串字节。
- `residue`：`map` 的属性，以及根节点以外、直接挂在 `map` 上的元素。
- `nodes`：每个 `node` 的全部属性（含 `ID`、`CREATED`、颜色）和子元素（`icon`、`font`、`edge`、`cloud`、`arrowlink`、`attribute`、`hook`、`encrypted_content`、`richcontent`）。改了这一项的映射字段之后，只覆盖变了的属性，其余按读入时的值写回。
- `ID_` 加 32 位十六进制是本 codec 写出的 id，导入时复用为节点 UUID。其他 `ID` 原样写回，模型里另用一个 UUID。

样本在 `Tests/FlorettaCoreTests/Fixtures/MM/`。`MMFieldCatalog` 与下表是同一份清单，单测会对照。

## 三类样本

| 类 | 文件 | 覆盖 |
|---|---|---|
| simple | `simple.mm` | 单根、两个子节点 |
| nested | `nested.mm` | 五层，折叠、左右侧、链接和备注 |
| passthrough | `passthrough.mm` | 图标、字体、边、云、箭头、颜色、富文本标记和 DETAILS |

## 字段

| 字段 | 处理 | 说明 |
|---|---|---|
| `source bytes` | passthrough | 映射快照没变时，导出就是导入的原字节 |
| `map attributes` | passthrough | version 和其他 map 属性写回 |
| `TEXT` | mapped | 非空时作为 text |
| `richcontent NODE plain` | mapped | TEXT 为空时作为 text；两边都有且不同时写入 note |
| `richcontent NOTE plain` | mapped | note；多个 NOTE 时模型留下最后一段纯文本 |
| `richcontent markup` | passthrough | 映射出的纯文本没变时原样写回；NOTE 纯文本变了就重写 NOTE；NODE 富文本在文字变了、或它曾被折进 note 且 note 变了时丢掉 |
| `richcontent DETAILS` | passthrough | 不进 note，整段写回 |
| `LINK` | mapped | link |
| `FOLDED` | mapped | isCollapsed；只有 true 算折叠 |
| `POSITION left/right` | mapped | side |
| `POSITION other` | gap | 导入报 unknownPosition，不猜 |
| `ID` | mapped | ID_ 加 32 位十六进制复用为 UUID；其他字符串写回，模型另用新 UUID |
| `CREATED MODIFIED` | passthrough | 不是文档的 createdAt / modifiedAt |
| `color attributes` | passthrough | COLOR、BACKGROUND_COLOR、STYLE 不进 MindMapNodeStyle |
| `icon font edge cloud attribute hook arrowlink encrypted_content` | passthrough | 元素写回，不变成节点；arrowlink 不是 TopicRelationship |
| `children order` | mapped | children 顺序 |
| `free position` | gap | .mm 没有 x/y |
| `freeNodes` | gap | 不写进 .mm |
| `stickies` | gap | 便签不是主题 |
| `regions` | gap | 专区不是主题 |
| `model style` | gap | Floretta 自己的样式不写进本来没有这些属性的 .mm |
| `relationships` | gap | 不写成 TopicRelationship；arrowlink 仍按元素写回 |
| `multiple roots` | gap | 导出多个根时用文档标题包一层；文件里已有的多个根在映射没变时按原字节写回 |
| `comments and doctype` | gap | 未改映射时留在原字节里；改过之后不重写 |
| `external entity` | gap | 拒绝解析 |

处理只有三种：`mapped` 进模型并在导出时从模型写出；`passthrough` 不解释，原值写回；`gap` 是已知做不到的地方，不是静默丢掉正文。

颜色、图标、箭头不进模型，所以画布上看不到它们。文件里还在。用户没改映射字段时，这些字节原样回去。改了节点文字之后，颜色和图标仍写回；备注的富文本标记会换成纯文本 `<p>`，因为备注本身变了。

改了映射字段之后，属性顺序按名字排序。没改时不重写。把改过的字段改回去之后，再次导出回到导入时的原字节。未知的 `POSITION` 仍然直接报错。
