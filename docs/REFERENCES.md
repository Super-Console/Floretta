# 参考的开源实现（可借鉴 / 不可复制）

调研时间：2026-11-09。以下信息来自各仓库 README、许可证文件与平台声明；**未做逐模块源码审计**。

| 项目 | 形态 | 平台 | 许可证 | 我们能借鉴什么 | 踩坑点 |
|---|---|---|---|---|---|
| [Mindscape](https://github.com/jiuxianzai/Mindscape) | 完整 Mac 思维导图 | macOS 14+ | MIT | 中文输入法组字时的节点宽度处理、折叠控件、快捷键设置界面 | 画布是 AppKit `NSView` 自绘，iOS 不能直接复用；数据存 SQLite，不是单文件 |
| [Brainstorm](https://github.com/eugenepyvovarov/brainstorm) | 完整 Mac 思维导图 | macOS | MIT | 键盘优先的交互取舍、单文件 JSON（`.bs`）、导出 HTML 演示模式 | macOS 专用；自有格式不通用 |
| [SwiftFlow](https://github.com/aaurelions/SwiftFlow) | 节点画布**组件**（不是 App） | iOS + macOS | 页面标 MIT（根 LICENSE 未读到，需再核） | 画布平移缩放/节点拖动/连线/JSON 序列化的结构组织 | 只是画布，不含思维导图布局和编辑体验；README 写 iOS 16，`Package.swift` 写 iOS 17，以源码为准 |
| [Freeplane](https://github.com/freeplane/freeplane) | 完整桌面导图 | Win/Mac/Linux (Java Swing) | **GPL-2.0** | `.mm` 格式的语义参考、节点/属性模型 | **不能复制代码**进闭源或私有项目；无官方移动端 |
| [SimpleMindMap](https://github.com/wanglin2/mind-map) | JS 导图库 | Web | MIT | `.xmind` 解析思路（ZIP + `content.json`） | 是 Web 技术栈，只能读思路不能搬实现 |

## 边界

1. **只借鉴交互与数据结构的思路，不复制代码**。除 MIT 项目在满足署名条件时可复用外，
   GPL 项目（Freeplane）一律只读参考。
2. MIT 项目若确实要复用代码：保留版权与许可声明，并在 `NOTICE` 里列出来源与版本。
3. **不把上游项目名、Logo 写进我们的产品界面**，避免暗示官方关系。
4. 参考项目多为新项目（星标少、版本号早期），**其"已实现"的自述不等于我们实测过**。

## 已否决的路线

- ❌ 以 Freeplane 为底座改 UI：Java/Swing 无法变成 SwiftUI 原生三端，且 GPL 约束。
- ❌ 以 Electron/Web 导图库套壳：与"原生"目标冲突。
- ❌ 直接 fork 某个新生 Mac 项目：三端需求对不上，改造成本高于重建模型层。
