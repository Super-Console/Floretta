# FORMAT-FOR-AI（草案 · S0）

> 状态：随 `docs/MD-AS-DOCUMENT.md`（已通过 Censor）一并落地的 AI 读写约定。  
> 范围：Interop；描述 **地址、可写字段、拒绝项**，不规定具体 RPC 传输层。

## 1. 文档模式

| 打开文件 | 模式 | 节点身份 |
|---|---|---|
| `.floretta` | 完整工程 | 稳定 UUID |
| `.md` | Markdown 模式 | **路径**（见下）；临时 UUID 仅内存，**禁止**当作 AI 地址 |

## 2. Markdown 路径（0-based）

- `root` = `document.roots` 森林。
- `root/<i>/<j>/...`：每一段为 **从 0 起的兄弟下标**，与文件中列表顺序一致。
- 例：`root/3/1` = 第 4 个根下的第 2 个子节点。
- 分区标题根（仅 `# `）与普通根共用同一套索引。

### 2.1 路径失效

插入、删除、移动会改变后续兄弟下标。调用方 **必须** 在变更后按最新树重算路径；不得缓存旧路径当稳定 id，也不得把临时 UUID 当路径别名对外使用。

## 3. 可读写字段（md 模式）

| 操作 | 允许 |
|---|---|
| `get text \| note \| link @ path` | 是 |
| `set text \| note \| link @ path` | 是（可持久化进 `.md`） |
| `insert child \| sibling @ path` | 是 |
| `delete @ path` | 是 |
| `move @ from → to` | 是（细节可后续补） |

## 4. 拒绝（md 模式）

下列写入 **必须拒绝**，返回明确错误（与 UI 置灰文案一致）：

- 颜色 / 样式
- 附件
- 关系线
- `position` / `side` / `isCollapsed`

错误语义示例：`Markdown 模式无法保存颜色`（具体错误码由实现定，文案对齐 `MD-AS-DOCUMENT` §3.2）。

## 5. `.floretta` 差异摘要

| | `.floretta` | `.md` |
|---|---|---|
| 身份 | UUID | `root/3/1` 路径（易变） |
| 可持久化 | 全模型（产品开放范围内） | text / note / link / 结构 + front-matter |
| 颜色等 | 可写（若开放） | 拒绝 |

## 6. 与规格的关系

完整映射、失败语义、front-matter、列表标记见 `docs/MD-AS-DOCUMENT.md`。本文件不重复 codec 细则。
