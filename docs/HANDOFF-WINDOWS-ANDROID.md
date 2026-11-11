# Windows / Android 多平台交接

本文供未来启动 Windows 或 Android 客户端时使用。依据 `docs/ADR-021-platform-layering.md`、`docs/FORMATS.md` 和当前源码结构盘点，日期：2026-11-11。数字为本次对当前工作树文件现查结果，不是路线承诺。

## 当前平台分层

| 层 | 当前职责 | 跨平台策略 |
|---|---|---|
| `FlorettaCore/` | 文档模型、ZIP 容器、格式 codec、布局、键盘命令、自动保存、撤销与 CLI/MCP 语义 | 64 个 Swift 源文件；Core 约束为纯 Foundation，不依赖 SwiftUI / AppKit / UIKit / SwiftData，也不允许 `#if os(...)`。可复用的前提是目标平台可构建并满足 Foundation API。 |
| `FlorettaUI/` 与 `Floretta/` | SwiftUI 视图、画布、编辑器、应用入口及平台扩展 | 当前找到 39 个 Swift 源文件，其中 24 个直接 `import SwiftUI`。Windows UI 必须重写；Android UI 也必须重写，不能把 SwiftUI 层当作可移植 UI。 |
| 平台能力 | 文件访问、剪贴板、设备信息、时钟、字体测量等 | `FlorettaCore/Ports/PlatformPorts.swift` 声明协议；各平台提供适配实现。当前 ADR 记录 Apple 端实现，Windows/Android 实作尚未验证。 |

文件计数命令口径：`find FlorettaCore -type f -name '*.swift'`；UI 计数为 `find FlorettaUI Floretta -type f -name '*.swift'`，SwiftUI 计数再筛 `import SwiftUI`。Core 的平台禁用项由 `scripts/check-floretta-core-imports.sh` 检查；这不等于所有 64 个文件都只写了一个 `import Foundation`，应以真实依赖和构建结果为准。

## 文件格式与附件容器

- `.floretta` 是 ZIP 容器，核心文档数据为 `document.json`，另有元数据和附件容器；附件字节位于 `assets/<sha256>.<ext>`。引用计数、哈希校验与孤儿附件回收由 Core 维护。跨平台实现要按 `docs/FORMATS.md`、`docs/ATTACHMENTS.md` 和 `docs/STREAMING.md` 处理，不能把整个大附件一次性读入内存、重压缩或转码。
- `.xmind` 读写 ZIP 中 `content.json`；未知字段及原始 zip 条目按规格 pass-through。仅有旧版 `content.xml` 的文件明确不导入。其他格式边界详见 `docs/FORMATS.md` 与对应字段表。
- 写入应保持原子替换与附件校验语义；对未知字段不得静默丢弃。独立实现时用真实样本做未修改字节往返、修改字段后再导入、损坏容器失败等测试。
- `docs/FORMATS.md` 明确：Markdown、OPML、FreeMind、TextBundle、PNG/PDF 只导出当前画布；`.xmind` 可保留多画布。不要将某格式的能力误认为容器通用能力。

## 已验证与未验证

**已有结构性保障**

- Core 禁止导入 SwiftUI / AppKit / UIKit / SwiftData 及平台条件编译的脚本检查已接入 CI（`docs/ADR-021-platform-layering.md`、`.github/workflows/floretta-core.yml`）。本次文档任务另会运行该脚本。
- Core 有多格式 codec、容器和附件实现；具体样本覆盖/保真声明以 `docs/FORMATS.md` 验收表及对应测试为准。

**明确限制 / 尚未验证**

- 无人值守 SSH 会话无法为带 Share / Quick Look 扩展的 target 签名；钥匙串不可用会报 `errSecInternalComponent`。`CODE_SIGNING_ALLOWED=NO`、`ENABLE_DEBUG_DYLIB=NO` 也不能绕过。签名构建、归档和上传应在 Mac 图形会话中完成；SSH 侧限于结构检查和 Core 测试（仓库 `AGENTS.md`）。
- Windows 与 Android 的 Core 编译、平台 Ports、文件授权/原子替换、字体指标、剪贴板、附件大文件流式处理及 UI 均未因本架构文档而得到验证。
- ADR 中“23 个纯逻辑文件、12 个 SwiftUI 视图、约 65%”是先前记录的基线；当前重新计数为 Core 64 个 Swift 文件、UI/App 共 39 个 Swift 文件（其中 24 个直接导入 SwiftUI），计数口径不同，不能直接用百分比相减或当作代码可复用率。

## 建议路线（估算，不是承诺）

下面区间是初步工程估算，假设 Core 依赖兼容、格式规格稳定、仅做一个可用客户端；不含发布审核、完整无障碍、本地化、云同步、第三方格式扩展与长期维护，实际工期需先做原型和平台验证。

| 阶段 | 建议工作 | 初步估算 |
|---|---|---|
| 0. 可行性 spike | 在 Windows / Android 目标工具链编译 Core；列出不兼容 Foundation API；对文件原子写、ZIP 流、SHA-256、10GB 软上限建小测试 | 约 1–2 周 |
| 1. 平台 Ports | 实现文件访问与安全授权、剪贴板、设备信息、时钟、字体测量；验证恢复/权限撤销与大附件 | 约 2–5 周 |
| 2. 原生最小 UI | 打开/新建/保存、画布/树导航、节点编辑、撤销、基本文件导入导出；遵循目标平台原生控件 | 约 6–12 周 |
| 3. 产品能力补齐 | 附件预览、检查器、导出、无障碍、键盘/触控、错误恢复、格式往返与性能验收 | 约 6–16 周以上 |

建议 Windows 与 Android 分成独立 spike，不先承诺共享 UI 技术栈。每阶段以可运行原型和真实文件验收重新估算；若 Swift Core 无法在目标平台维护，才评估以规格/测试为合同重实现 Core，而不是先迁移 UI。
