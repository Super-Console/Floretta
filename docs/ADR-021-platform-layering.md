# ADR-021 平台分层与多平台预留

状态：已采纳（2026-11-10）
决策人：Timmy
执行：Floretta Core 抽取

## 背景

产品当前支持 macOS / iPadOS / iOS，三端共用一份 SwiftUI 代码库。用户明确：
macOS 是 T0（任何新功能先在苹果端发），但未来很可能扩展到 Windows，甚至 Linux。
现在不做 Windows/Linux，但要留出不返工的门。

## 决策

### 1. 三层结构（强制）

```
FlorettaCore        —— 纯 Foundation，禁止 import SwiftUI / AppKit / UIKit / SwiftData
FlorettaUI          —— SwiftUI 视图层，可依赖 Core，禁止被 Core 依赖
FlorettaApp-<平台>   —— 入口、平台能力实现、打包
```

- `FlorettaCore` 承载：文档模型、ZIP 容器、四种格式解析与导出、布局引擎、
  键盘命令映射、自动保存、撤销栈、CLI/MCP 的操作语义。
- `FlorettaUI` 承载：所有视图、手势、材质、动画。
- 平台差异不进 Core，而是以**协议**形式由各平台实现。

### 2. 平台能力用协议注入（Ports）

Core 只声明协议，不写实现：

| 协议 | 作用 | macOS / iOS 实现 |
|---|---|---|
| `FileAccessPort` | 打开/保存/监听文件，安全作用域书签 | NSFileCoordinator + 安全书签 |
| `PasteboardPort` | 读写剪贴板文本 | NSPasteboard / UIPasteboard |
| `DeviceInfoPort` | 设备名、型号标识（用于「我的 iPhone / 我的 iPad」） | UIDevice / Host |
| `ClockPort` | 时间戳（便于测试与跨平台一致） | Foundation |
| `FontMetricsPort` | 文字测量（布局需要，平台字体不同） | CoreText |

规则：**Core 里出现任何平台判断（`#if os(...)`）都算违规**，除编译期常量外一律走协议。

### 3. 编译期强制，不靠自觉

- 在 `Package.swift` 里把 Core 的依赖声明为 `.product(name: "Foundation")` 级别，
  不链 SwiftUI。
- 加一条 CI / 本地脚本检查：`grep -rE "^import (SwiftUI|AppKit|UIKit)" FlorettaCore/`
  命中即失败。
- 加一条检查：`grep -rn "#if os(" FlorettaCore/` 命中需要说明理由。

### 4. 文件格式是跨平台的地基

不管将来 Windows / Linux 用 Swift、C# 还是 Rust 重写界面，
**只要读写同一份 `.floretta` 容器与 `.xmind` 互通格式，用户的文件就不会丢**。
因此格式规范（`docs/FORMATS.md`）与 AI 接口（`docs/FORMAT-FOR-AI.md`）
的稳定性优先于任何单平台特性。

### 5. 平台优先级

| 平台 | 优先级 | 说明 |
|---|---|---|
| macOS | **T0** | 新功能首发，设计基准 |
| iPadOS / iOS | T0 | 与 macOS 共享同一套设计逻辑 |
| Windows | 未启动 | 需另选 UI 栈（WinUI 3 或原生 Rust/C++），Core 可复用 |
| Linux | 未启动 | 同上，GTK4 / Qt 均可 |

### 6. 迁移成本预估（当前基线）

- 纯逻辑文件 23 个（约 65%），可直接复用
- SwiftUI 视图 12 个，任何非 Apple 平台都必须重写
- Core 抽取完成后，Windows 版的工作量集中在 UI 层

## 不做什么

- 不用 Electron / Tauri / Flutter 套壳换跨平台
- 不为了跨平台牺牲 Apple 端原生体验（液态玻璃、指针交互、快捷键）
- 不在没有实际需求时提前写 Windows/Linux 代码

## F3 核实记录（2026-11-11）

以下结论按当前源码核实；「部分」表示 Core 协议/适配器存在，但调用方仍有直连或注入未贯通，不等于完整 Port 化。

| Port | 结论 | 文件证据与缺口 |
|---|---|---|
| `FileAccessPort` | **部分** | 协议在 `FlorettaCore/Ports/PlatformPorts.swift`；`Floretta/Shared/Ports/ApplePlatformPorts.swift` 有 `FoundationFileAccess` 和 `ApplePlatformPorts.current()`；`FlorettaCore/Container/DocumentContainer.swift` 的 `read/save` 可接收注入。缺口：`ApplePlatformPorts.current()` 的构造结果没有贯穿 UI/文档会话；`Floretta/Shared/Shell/DocumentSession.swift`、`DocumentEditor.swift` 等仍直接用 `FileManager`，适配器也明确尚未实现安全作用域书签与 `NSFileCoordinator`。流式端另有 `StreamingFilePort`，不能据此认定全部文件操作已走 Port。 |
| `PasteboardPort` | **部分** | 协议及 macOS `NSPasteboard` / iOS `UIPasteboard` 实现位于 `FlorettaCore/Ports/PlatformPorts.swift`、`Floretta/Shared/Ports/ApplePlatformPorts.swift`。缺口：`Floretta/Shared/Shell/DocumentEditor.swift` 约 2133、2176、3162 行直接读写系统剪贴板，未经注入 Port。 |
| `DeviceInfoPort` | **部分** | 协议及 `SystemDeviceInfo` 适配器在上述两个 Port 文件中。缺口：`Floretta/Shared/Shell/AppSettings.swift` 约 411 行、`Floretta/Shared/Shell/LocalDeviceLabel.swift` 约 28 行直接查询 `UIDevice.current.userInterfaceIdiom`；应用层未统一消费 `ApplePlatformPorts.device`。 |
| `ClockPort` | **部分** | 协议和 `SystemClock` 在上述 Port 文件；`FlorettaUI/FlorettaUI.swift` 暴露 `now(clock:)`，但这是薄封装。缺口：`FlorettaCore/AI/FlorettaAISession.swift` 约 477 行直接 `Date()`，且 `MindMapDocument.swift` 初始化默认值、`ShareIngress.swift` 默认参数等直接取系统时间；没有贯通的时钟注入。 |
| `FontMetricsPort` | **部分** | 协议在 `FlorettaCore/Ports/PlatformPorts.swift`；`TextMeasurementCache` 接收 Port，`FlorettaCore/Layout/EstimatedFontMetrics.swift` 提供 Core 默认实现，`Floretta/Shared/Canvas/CanvasPlacement.swift` 注入 `CoreTextFontMetrics`。缺口：`Floretta/Shared/Keyboard/NodeTextEditor.swift` 直接用 `NSFont` / `UIFont` 做编辑字体测量/布局；Port 只覆盖布局的一部分，且调用处直接构造适配器，不是统一依赖注入。 |

因此，五个协议都不只是文档：它们已声明在 Core，并有不同程度的实现；但当前不能把五项中的任何一项报告为完整贯通的 UI Port。此记录不新增空协议，也不把仍在直调系统 API 的路径计作完成。
