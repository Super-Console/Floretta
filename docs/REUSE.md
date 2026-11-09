# 复用优先：现成实现清单与判定

> 原则（Timmy 2026-11-09 明确）：**能拿现成的就不自己写**。别人已经把难点做完的（哪怕只有核心、没有 GUI），
> 直接拿来用或改编；自研必须是"看过现成的、确认不能用的"之后的选择。

## 一、判定流程（每个新模块必走）

1. 先查 `docs/REFERENCES.md` 和本文档有没有候选；
2. 有候选 → 读它的许可证与实现方式，写清楚能不能直接用；
3. 能用 → 用（vendor 进来或作为 SPM 依赖），在 `NOTICE` 记来源与版本；
4. 不能用 → 在 `docs/STATUS.md` 写"看过谁、为什么不能用"，然后才自研；
5. **不允许**出现"我们重新实现了一遍 X"却不说明为什么不复用。

## 二、当前能力 → 候选 → 结论

| 能力 | 现成候选 | 许可证 | 结论 | 说明 |
|---|---|---|---|---|
| 节点画布/视口变换/命中测试/JSON 序列化 | **SwiftFlow**（aaurelions/SwiftFlow） | MIT（页面标 MIT，根 LICENSE 需再核） | **优先采用** | 它就是"没有 GUI 的 ReactFlow"式组件，正好是 P1-1 我们自己写的部分。iOS 17 / macOS 13 起 |
| 中文 IME 在画布上的处理 | **Mindscape**（jiuxianzai/Mindscape） | MIT | **参考实现** | 它专门解决"组字时节点变宽、候选框贴光标"；可在 MIT 前提下移植其做法 |
| 键盘优先的编辑模型 | **Brainstorm**（eugenepyvovarov/brainstorm） | MIT | **参考实现** | Tab/Return/方向键的行为与命令分层可直接对照 |
| `.xmind` 解析（zip + content.json） | **SimpleMindMap**（wanglin2/mind-map，JS） | MIT | **只借结构** | 不能直接搬 JS，但它的字段映射与边界处理是最完整的公开资料 |
| `.mm`（FreeMind/Freeplane）读写 | Freeplane | **GPL-2.0** | **禁止复制代码** | 只按公开 XML 结构自行实现 |
| 树形/双侧布局算法 | 无成熟 Swift 库 | — | 自研（已做） | 通用图布局库（yFiles 等）商业授权，且不是思维导图语义 |

## 三、下一步：P1-r 复用评审（插在 P1-c 之后）

目的：把"已经自己写了但本可以复用"的部分找回来。

- **P1-r-1** 引入 SwiftFlow 作为 SPM 依赖（vendor 到 `Vendor/SwiftFlow` 或 `Package.swift` 依赖），
  用它替换我们自研的 viewport 变换、命中测试；**保留我们自己的 LayoutEngine**（它负责思维导图语义，SwiftFlow 不提供）。
- **P1-r-2** 对照 Mindscape 的 IME 方案，检查我们编辑态的实现差异，把"组字期间节点变宽/候选框位置"对齐；
  如采用其代码，在 `NOTICE` 注明来源与 MIT 条款。
- **P1-r-3** 写 `NOTICE`：列出所有第三方来源、版本、许可证与改动说明。
- **P1-r-4** 产出 `docs/REUSE-AUDIT.md`：逐模块回答"用了谁 / 为什么不用 / 差异是什么"。

**验收**：`swift build` 与 `xcodebuild test` 全绿；`NOTICE` 存在且与依赖一致；
`REUSE-AUDIT.md` 每一行都有结论，没有"没查过"。

## 四、交付路径（Timmy 的验收方式）

| 阶段 | 渠道 | 谁做 |
|---|---|---|
| 代码 | GitHub 仓库（先私有，P4 前转公开并附 LICENSE/NOTICE） | 执行者 commit，总指挥验收 |
| 可运行版本 | TestFlight 内部测试，邀请 `timmysh34@icloud.com` | 总指挥在 Pro 上归档上传 |
| 真实体验验收 | Timmy 本人在 iPhone / iPad / Mac 上试 | Timmy |

公开仓库前必须做一遍清理：移除内部路径、主机名、私钥、个人邮箱、未授权素材。
LICENSE 与 NOTICE 未定之前不转公开。
