# 状态

## 当前阶段

P0-1 已由总指挥验收（合并 `ef9e4f2`；本机 `xcodebuild` macOS 与 iOS Simulator 均为 BUILD SUCCEEDED，`UIDeviceFamily = [1, 2]`）。

P0-2 文档模型与 `.floretta` codec 已落盘。总指挥在 Pro 上跑测试时，`testMissingAndMistypedVersionThrow` 失败：类型不对的 `formatVersion` 被说成「不是 .floretta JSON」。这一批只修这条错误映射。P0-4、界面、画布、图标、P4 都没做。

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

## 下一步

本机 Mac 拉取后运行：

```bash
xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS'
```

构建或测试错误贴回再改。通过后再放行下一批。

## P0-2 申报

共享模型（`Floretta-macOS` 与 `Floretta-iOS` 都编译，测试 target 也编译同一份）：

- `Floretta/Shared/Model/MindMapNode.swift`：`id`（UUID）、`text`、`note`、`isCollapsed`、可选 `style`（版本 1 只有 `colorHex`）、有序 `children`
- `Floretta/Shared/Model/MindMapDocument.swift`：`title`、`createdAt`、`modifiedAt`、`formatVersion`（当前为 1）、有序 `roots`（可以多个，也可以为空）
- `Floretta/Shared/Model/FlorettaCodec.swift`：单文件 `.floretta`，JSON、UTF-8、pretty-printed、`sortedKeys` 字母序。时间戳写成 ISO-8601 UTC，精确到秒
- 类型是 `Sendable`、`Codable`、`Equatable`。没有第三方依赖

环与重复 id：内存里的节点是值类型树，JSON 也没有指针，所以文件里表达不出真正的指针环。解码时整棵树收集 id：子节点复用祖先 id 抛 `cyclicID`；其他重复抛 `duplicateID`。坏文件、非 UTF-8、缺字段、错误类型、版本不是 1，都抛 `FlorettaCodecError`，没有 `fatalError`。嵌套超过 512 层编码路径时抛 corrupt，避免恶意文件把栈打爆。

§1.1：没有改窗口，没有自绘控件，没有需要报批的自定义控件。

§1.2：看过 `docs/REFERENCES.md`。Mindscape 用 SQLite，不是单文件。Brainstorm 的 `.bs` 是另一套 JSON，仓库里没有其源码，不复制。SwiftFlow 是自由画布，不是带格式版本的有序大纲。任务书已经规定 `.floretta` 的字段，所以模型是自己写的，没有引入依赖，也没有拷贝 MIT/GPL 代码。

没有注册系统文件类型（`UTType` / `CFBundleDocumentTypes`）。codec 编译不需要它，这一批也没有文档 UI。

`docs/FORMATS.md` 仍写 `.supernode`。任务书写的是 `.floretta`。这一批没有改格式矩阵，避免把未验收的格式写成已支持。

测试：`FlorettaTests`（macOS XCTest，不挂 host app，零第三方）。已放进共享 scheme `Floretta-macOS` 的 Test 动作。`Floretta-iOS` scheme 没有挂这个 bundle，因为 XCTest bundle 是单平台的，iOS 目的地跑不了 macOS 的 `.xctest`。模型源码仍然编进 `Floretta-iOS`。

任务书里 P0-3 的「建树 → 编解码 → 结构与文字一致」和「坏文件 / 环要报错」按总指挥要求写进了这一批。没有另做 P0-3 的 1000 节点脚本。P0-4 自动保存没做。

### 已验证

1. `command -v xcodebuild swift swiftc`：都不在 PATH。没有跑 `xcodebuild`，没有伪造测试日志。
2. Python 解析 `project.pbxproj`：61 个对象 ID，均为 24 位十六进制，引用闭合。三个 target：两个 app 的 Compile Sources 都含 `MindMapNode.swift`、`MindMapDocument.swift`、`FlorettaCodec.swift`；`FlorettaTests` 编译这三份再加上 `MindMapDocumentTests.swift`。无 package 引用。引用的源文件都在磁盘上。
3. `plistlib`：`Floretta/iOS/Info.plist` 的 `UIDeviceFamily` 仍是 `[1, 2]`。
4. 两个 scheme 的 XML 可解析。`Floretta-macOS` 的 Testable 指向 `E20000000000000000000001`（`FlorettaTests`）。

### 未验证

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

- `xcodebuild test` 没跑。不能说测试通过，也不能说工程能编译
- Swift 6 严格并发下这些文件能否编译。本机没有 `swiftc`，也没有 Apple Foundation / XCTest SDK
- ISO-8601 往返、pretty-print 的冒号空格、`sortedKeys` 的实际字节，都没在 Apple 的 `JSONEncoder` 上见过
- 空 App Icon、签名、部署目标 26.0 这次没有复测

## 记录

| 日期 | 批次 | 结果 | 备注 |
|---|---|---|---|
| 2026-11-09 | 仓库初始化 | 完成 | 骨架、任务书、格式矩阵、参考清单落盘 |
| 2026-11-09 | 环境就绪 | 完成 | Pro 工作副本 + push 凭据实测可推 |
| 2026-11-09 | 任务书合并 | 完成 | 主线任务 + App 图标任务合并进 TASKBOOK-001；产品名定为 Floretta；图标参考图入库 |
| 2026-11-09 | 约束追加 | 完成 | 新增 D-8 原生控件 / D-9 复用开源 / D-10 TestFlight 交付；已写入 TASKBOOK 1.1、1.2、5.1 |
| 2026-11-09 | P0-1 | 总指挥验收通过 | 合并 `ef9e4f2`。本机 xcodebuild macOS 与 iOS Simulator BUILD SUCCEEDED |
| 2026-11-09 | P0-2 | 总指挥测试未过 | `testMissingAndMistypedVersionThrow`：字符串或非整数 `formatVersion` 报成「不是 .floretta JSON」，测试要「Wrong JSON type」 |
| 2026-11-09 | P0-2 修复 | 已提交，云端未复测 | 解码前先看 JSON 类型。`formatVersion` 不是整数、以及其它必填字段类型不对，抛 `.corrupt("Wrong JSON type at …")`。语法错误仍是「不是 .floretta JSON」。云端不能跑 xcodebuild |
