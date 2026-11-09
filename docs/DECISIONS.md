# 决策记录

每条：决策 + 理由 + 影响 + 状态（已定 / 待定）。

## D-1 只做 Apple 三端（macOS / iPadOS / iOS）

- **决策**：第一阶段不做 Windows 和 Android。
- **理由**：Timmy 相关设备是 iPhone/iPad/Mac；Apple 端可共享 Swift 代码与同一套文档模型。
- **影响**：不做跨平台共享核心（Rust/C++ 之类）的架构预留，避免为不存在的需求付复杂度。
- **状态**：已定（2026-11-09）。

## D-2 原生实现（Swift + SwiftUI/AppKit/UIKit），不用 WebView 承载编辑

- **决策**：画布与编辑体验用系统原生技术实现。
- **理由**：Timmy 明确要"苹果原生控件"；Web 画布在 IME、滚动手感、性能上反复翻车。
- **状态**：已定。

## D-3 数据存单文件 `.floretta`（JSON），不存数据库

- **决策**：一张导图 = 一个文件，人可读。
- **理由**：符合 Timmy"文件可带走、可被其他工具读"的习惯；便于 iCloud Drive 逐文件同步与版本备份。
- **代价**：超大导图（万级节点）需要增量写入策略；P0 先做全量写 + 自动保存。
- **状态**：已定。

## D-4 格式策略：先 `.mm`/`.opml`/Markdown，XMind 只导入

- **决策**：见 `docs/FORMATS.md`。
- **理由**：开放格式能真正保证不锁死用户；闭源格式做"尽力导入"即可，不承诺无损。
- **状态**：已定。

## D-5 产品命名：Floretta

- **决策**：产品名定为 **Floretta**（Timmy 决定，2026-11-09）。
- **已排除**：
  - `Supermind` —— 与 Xmind 背后的公司品牌冲突（supermind.world 是 Xmind 团队的公司站），
    且 App Store 已存在同名思维导图应用 `SuperMind: Mind Mapping`（上海语数科技）。
  - `Supernode` / `Ramify` —— 曾作为候选与工作代号，未采用。
- **已知遗留**：App Store 上已有一个叫 `Floretta` 的应用（开发者 晓东 毛，品类 **Games**）。
  Apple 的 App 名称在商店内唯一，因此上架时**不能只用 "Floretta" 单词做展示名**，
  需要副标题或后缀（如 "Floretta: Mind Map"），或届时再评估改名。
  该应用是游戏，不是同类竞品，不构成产品层面的直接冲突。
- **未做**：USPTO / CNIPA 商标检索。正式上架前需补。
- **状态**：已定（名称）／上架展示名待定。

## D-6 版本控制与上传

- **决策**：私有 GitHub 仓库，每完成一个步骤即 commit + push。
- **状态**：已定。

## D-7 开源计划

- **决策**：目标开源，但仓库先保持私有，等核心体验（P1）跑通再决定公开时点与许可证。
- **理由**：避免半成品被当成可用的成品；也给许可证选择留出时间（不沿用任何 GPL 上游代码）。
- **状态**：待定（时点与许可证）。

## D-8 UI 只使用 Apple 官方原生控件

- **决策**：所有界面元素用 SwiftUI / AppKit / UIKit 原生控件；禁止自绘按钮、滑块、开关等。
  视觉风格只通过颜色、字体、间距、tint、材质表达。
- **理由**：Timmy 明确要求（2026-11-09）；原生控件自带键盘导航、VoiceOver、Dynamic Type、
  系统一致性，自绘会逐项丢掉这些。
- **例外流程**：确需自定义时，先写 `docs/STATUS.md` 报批，Timmy 同意后才可实施。
- **边界**：文档画布（节点绘制）属于内容视图，允许自绘；但画布上的交互控件仍须用系统控件。
- **状态**：已定。

## D-9 复用既有开源实现，不重复造轮子

- **决策**：画布视口、树形布局、键盘导航、序列化、格式解析，先查 Mindscape / Brainstorm /
  SwiftFlow（MIT）是否已有可用方案；能复用就复用，能借鉴就借鉴。
- **约束**：Freeplane 为 GPL-2.0，只读思路，不复制代码。新增依赖须报批并记录版本。
- **状态**：已定。

## D-10 首版交付方式：TestFlight 内部测试

- **决策**：第一版完成后直接上 TestFlight 内部测试，邀请 `timmysh34@icloud.com` 验收。
- **前置（已核实）**：Team `JY5U4D6JD3`、ASC API Key `GT622JVW4H`、Apple Distribution 证书均在位。
- **不做**：不提审、不做外部测试、不发公开链接。
- **状态**：已定。
## D-11 原生容器改为 ZIP（document.json + metadata.json + assets/）

- **决策**：`.floretta` 从纯 JSON 改为 ZIP 容器：`document.json`（内容树 + formatVersion + relations）、
  `metadata.json`（时间/应用版本/默认视图）、`assets/`（按内容哈希命名）。P1-1 之后、P2 之前一个批次完成。
- **理由**：附件与图片迟早要做；纯 JSON 只能 base64（体积 +33%、diff 失效），之后必然推倒重来。
  ZIP 仍是单文件，符合"用户自己管文件"，且适配 FileWrapper 原子写。
- **代价**：ZIP 是二进制，Git 无法 diff。**补偿**：提供"导出为解压文件夹"与 Markdown 导出；
  不把容器做成目录 package（微信/邮件传输会碎）。
- **实现约束**：抽象 `DocumentContainer` 协议；JSON 保留为只读 legacy，ZIP 为默认写入。
- **状态**：已定（2026-11-09，Timmy 批准）。

## D-12 文档层统一 DocumentGroup + ReferenceFileDocument

- **决策**：三端统一 `DocumentGroup` + `ReferenceFileDocument`，不用 `NSDocument`。
- **理由**：共用一套文档生命周期，窗口/标签、自动保存、版本浏览器由系统接管；Reference 语义避免每次保存复制全量。
- **约束**：iOS 需 `LSSupportsOpeningDocumentsInPlace`，支持"文件"App 直接打开。
- **状态**：已定。

## D-13 关系线进 MVP

- **决策**：非树状关系线（from/to/label，按稳定 id 引用）进 MVP 数据模型。
- **理由**：只加数据字段、不加交互复杂度；后加要动模型与导入导出映射。
- **约束**：树仍是唯一真源；删节点级联删 relation。
- **状态**：已定。

## D-14 大纲视图提前到画布之后

- **决策**：P1-a 画布 → P1-b 布局 → P1-c 键盘 → **P1-d 大纲** → P2 格式。
- **理由**：同一棵树的第二个渲染器，成本低；iPhone 上几乎是唯一可用编辑形态。
- **状态**：已定。

## D-15 `.xmind` 只做导入

- **决策**：`.xmind` 仅导入（zip + content.json），不承诺导出与样式还原。
- **状态**：已定。

## D-16 两个前置实验（不写完整功能）

- **实验 A：中文 IME**。连续输入 200 字：组字时节点宽度、候选框位置、是否提前折行、Esc/方向键是否打断组字。
- **实验 B：iCloud 冲突**。两台设备改同一文件，必须"提示冲突"而非"静默覆盖"，确认 `NSFileVersion` 能枚举冲突版本。
- **状态**：已定（与 P1 并行，结论写 docs/measure.md 与 docs/STATUS.md）。

## D-17 图标与上架名

- **决策**：图标只按 `docs/design/app-icon-reference.png` 制作，不重绘；App Store 展示名不能只用 `Floretta`（已有同名 Games 应用），需副标题/后缀。
- **状态**：已定（P3 执行）。
## D-18 复用优先，不自造轮子

- **决策**：新模块先查现成实现（`docs/REUSE.md`），能用就用；自研必须先写"为什么不能用"。
- **边界**：MIT/Apache 可 vendor 并写 `NOTICE`；GPL/AGPL 只读思路、不复制代码。
- **落地**：新增 P1-r 复用评审批次，把 SwiftFlow 引入替换自研 viewport。
- **状态**：已定（2026-11-09，Timmy 明确）。

## D-19 交付：GitHub + TestFlight

- **决策**：代码走 GitHub（P4 前由私有转公开，附 LICENSE/NOTICE）；可运行版本走 TestFlight 内部测试，
  邀请 `timmysh34@icloud.com`；真实体验验收由 Timmy 本人在 iPhone/iPad/Mac 上做。
- **公开前置**：清理内部路径、主机名、私钥、个人邮箱与未授权素材。
- **状态**：已定。
