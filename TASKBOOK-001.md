# TASKBOOK-001 — Supernode 第一期（P0–P2）

> 读这份文件的是执行者（Grok Bot / 其他编码 agent）。总指挥（Hermes）负责边界与验收。
> **一次只做当前放行的批次**，做完就 commit + push，然后停下来等验收。

## 0. 项目定位（一句话）

用 Apple 原生技术做一款思维导图软件：Mac 上用键盘飞快录入，iPhone/iPad 上能顺手编辑，
文件留在本地、能导出成别的软件能读的格式。

## 1. 不可协商的技术约束

| 项目 | 要求 |
|---|---|
| 语言/框架 | Swift 6，SwiftUI 为主；画布可用 AppKit(macOS) / UIKit(iOS)，Core Graphics 绘制 |
| 工程形态 | 一个 Xcode 工程，**三个 target**：`Supernode-macOS`、`Supernode-iOS`（Universal = iPhone + iPad） |
| 禁止 | WebView/Electron/Flutter/React Native 承载核心编辑；禁止引入大而全的第三方导图 SDK |
| 最低系统 | macOS 26 / iOS 26（能在 Timmy 的真机上跑；如与实测不符以实测为准并记录） |
| 数据 | 本地优先，默认不联网、无账号、无遥测 |
| 依赖 | 尽量零第三方依赖；每加一个依赖必须在 PR/提交说明里写理由 |
| 许可证 | 只借鉴思想，不复制 GPL/AGPL 源码（尤其 Freeplane 是 GPL-2.0） |

## 2. 本期的"完成"定义

P2 结束时必须满足：

1. 能在 Mac 上建图并用 **Tab / Enter** 连续录入 20+ 节点不卡顿、不丢字。
2. 中文输入法（拼音）组字时节点宽度实时变化，候选框不飘。
3. 保存、关闭、重开，层级与文字完全一致。
4. Mac 上保存的文件能在 iPhone 和 iPad 上打开并继续编辑（顺序编辑，不做实时协作）。
5. 能导出 `.mm`（FreeMind/Freeplane）、`.opml`、Markdown；能导入 `.mm` 与 `.opml`。
6. 每一步都有提交并已 push 到 `main`。

---

## P0 — 仓库与数据模型（先做，做完停下）

**目标**：没有界面也要先有"导图是什么"的定义。

- P0-1 `Supernode.xcodeproj` 三 target 骨架，Mac 与 iOS 都能空跑起来（各一个空白窗口）。
  - iOS target 必须是 Universal：`UIDeviceFamily = [1, 2]`，iPad 不是拉伸的 iPhone。
  - 提交：`P0-1: three-target scaffold`
- P0-2 文档模型 `MindMapDocument`：
  - 节点：稳定 `id`（UUID）、文本、备注、折叠状态、可选样式、子节点有序数组。
  - 根节点可以多个（支持多中心/浮动主题）。
  - 文档级：标题、创建/修改时间、**格式版本号**（未来迁移用）。
  - 存成单文件：`.supernode`（JSON，UTF-8，人可读）。
  - 提交：`P0-2: document model + .supernode codec`
- P0-3 单元测试：建树 → 序列化 → 反序列化 → 结构与文字一致；环引用/坏文件要报错不崩溃。
  - 提交：`P0-3: document model tests`
- P0-4 自动保存与崩溃恢复：编辑中每 5 秒写临时副本；正常退出清理；异常退出后能提示恢复。
  - 提交：`P0-4: autosave + recovery`

**P0 验收**：`xcodebuild test` 通过；能用一个测试脚本生成 1000 节点的 `.supernode` 并被读回。

---

## P1 — Mac 画布与键盘录入（核心体验，最重要）

**目标**：像 XMind 一样"手不离键盘"地写。

- P1-1 画布：无限画布、滚轮/触控板平移、⌘+滚轮缩放、⌘0 适配、节点拖动。
  - 提交：`P1-1: canvas pan/zoom/drag`
- P1-2 自动布局：左右双向树形布局（根在中间，一级主题分左右），支持手动"记住位置"。
  - 提交：`P1-2: tree layout`
- P1-3 键盘模型（必须逐条实现并写测试）：
  - `Tab` 新建子节点并立即进入编辑
  - `Enter` 新建同级节点并立即进入编辑
  - `Shift+Enter` 节点内换行
  - 方向键在节点间移动；`Space` 进入编辑
  - `⌘⌫` / `Delete` 删除（带撤销）
  - `Esc` 取消编辑并还原
  - 提交：`P1-3: keyboard model`
- P1-4 撤销/重做（`⌘Z` / `⇧⌘Z`），至少覆盖：新建、删除、改文字、拖拽、折叠。
  - 提交：`P1-4: undo/redo`
- P1-5 中文输入法正确性：拼音组字期间节点宽度随候选变化、候选框贴光标、不提前折行。
  - 提交：`P1-5: IME-safe inline editing`
- P1-6 多选与批量移动/删除；折叠/展开（含"折叠后显示隐藏节点数"）。
  - 提交：`P1-6: multiselect + fold`

**P1 验收（总指挥实测，不看自述）**：
- 用真实中文内容连续录入 20 个节点，中途不切输入法、不丢字。
- 大小写/方向键/撤销都按上表行为走。
- 1000 节点导图的平移缩放仍然跟手（帧率与内存要有实测记录，写进 `docs/measure.md`）。

---

## P2 — 格式互通（"能带走"）

**目标**：不把用户锁死在本软件里。完整矩阵见 `docs/FORMATS.md`。

- P2-1 `.mm`（FreeMind/Freeplane XML）**导入 + 导出**：保留层级、文本、折叠、备注。
  - 注意：只按公开 XML 结构实现，不复制 Freeplane 源码。
- P2-2 `.opml` 导入 + 导出。
- P2-3 Markdown 导出（缩进列表；备注作为引用块或子项）与 Markdown 导入（标题/缩进→层级）。
- P2-4 `.xmind` **只做导入**：`zip` 包里的 `content.json`；解析失败要有清晰错误，不猜。
- P2-5 导出 PNG / PDF（用于分享和打印）。
- 每完成一项单独提交并 push：`P2-1: .mm import/export` 等。

**P2 验收**：用真实样本文件往返测试，把"保留了什么/丢了什么"逐项记进 `docs/FORMATS.md` 的验收表。
**不允许**在没有真实样本往返验证的情况下宣称"支持某格式"。

---

## 3. 本期明确不做（写死，防止跑偏）

- ❌ 实时多人协作、账号系统、云同步服务端
- ❌ AI 生成/总结（先不做，避免掩盖核心编辑体验的问题）
- ❌ Windows / Android
- ❌ 手绘自由画布、白板
- ❌ 主题商城、模板市场
- ❌ 在 P1 期间动 iPhone/iPad 布局（iPad 双栏留到 P3 再说）

## 4. 每批的交付物

1. 代码 + 提交（`P<阶段>-<序号>: <摘要>`）。
2. 已 push 到 `main`（见 `docs/WORKFLOW.md`）。
3. 一段"本批做了什么 / 没做什么 / 怎么验证"写在 commit body 或 `docs/STATUS.md`。

## 5. 卡住怎么办

- 卡住超过 30 分钟：停下来，在 `docs/STATUS.md` 写清"卡在哪、试过什么、需要什么决定"，
  然后等总指挥。**不许自己降级需求**（例如把原生画布换成 WebView）。
