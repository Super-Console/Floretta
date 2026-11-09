# 决策记录

每条：决策 + 理由 + 影响 + 状态（已定 / 待定）。

## D-1 只做 Apple 三端（macOS / iPadOS / iOS）

- **决策**：第一阶段不做 Windows 和 Android。
- **理由**：Timmy 相关设备是 iPhone/iPad/Mac；Apple 端可共享 Swift 代码与同一套文档模型。
- **影响**：不做跨平台共享核心（Rust/C++ 之类）的架构预留，避免为不存在的需求付复杂度。
- **状态**：已定（2026-11-09，Timmy 明确）。

## D-2 原生原生（Swift + SwiftUI/AppKit/UIKit），不用 WebView 承载编辑

- **决策**：画布与编辑体验用系统原生技术实现。
- **理由**：Timmy 明确要"苹果原生控件"；Web 画布在 IME、滚动手感、性能上反复翻车。
- **状态**：已定。

## D-3 数据存单文件 `.supernode`（JSON），不存数据库

- **决策**：一张导图 = 一个文件，人可读。
- **理由**：符合 Timmy"文件可带走、可被其他工具读"的习惯；便于 iCloud Drive 逐文件同步与版本备份。
- **代价**：超大导图（万级节点）需要增量写入策略，P0 先做全量写 + 自动保存。
- **状态**：已定。

## D-4 格式策略：先 `.mm`/`.opml`/Markdown，XMind 只导入

- **决策**：见 `docs/FORMATS.md`。
- **理由**：开放格式能真正保证不锁死用户；闭源格式做"尽力导入"即可，不承诺无损。
- **状态**：已定。

## D-5 产品命名

- **候选**：Supernode（工作名）／Ramify／待 Timmy 决定。
- **已排除**：`Supermind` —— 与 Xmind 背后的公司品牌冲突（supermind.world 是 Xmind 团队的公司站），
  且 App Store 已存在同名思维导图应用 `SuperMind: Mind Mapping`（上海语数科技）。
  同名同品类会同时伤害搜索、商标与审核。
- **状态**：待定。定名前不改 bundle ID、不上架、不公开宣传。

## D-6 版本控制与上传

- **决策**：私有 GitHub 仓库，每完成一个步骤即 commit + push。
- **状态**：已定。
