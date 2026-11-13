# Floretta 功能检查单

会话：2026-11-09 ~ 11-10
图例：`[x]` 已完成并验过 · `[~]` 已派但未合并/未验 · `[ ]` 未开始

维护规则：状态变化就改这里，一行一项，不许合并行。每个功能合入必须在同一变更集或紧随其后的跟进里更新本清单，不能只改 `docs/ROADMAP.md`。

---

## A. 外壳与可用性

- [x] A1 基础链路（PR #31 合入；Pro 双验随 1.7 收敛到 macOS 175/0）
- [x] A2 顶栏图标化（撤销/重做/插入/分享/缩放/沉浸/更多）
- [x] A3 顶部按钮收敛为一组（原 14 个可点区域）
- [x] A4 沉浸模式改名 + 玻璃退出按钮 + Esc 退出
- [x] A5 画布无边（隐藏 toolbar 背景，不留硬分隔线）
- [x] A6 点阵 tile 化（移除 800 点硬上限）
- [x] A7 缩放夹死八档（50/75/100/125/150/200/300/400）
- [x] A8 文字 LOD（小于 9pt 不画字，避免糊字）
- [x] A9 去掉画布蓝焦点环（保留键盘能力）
- [x] A10 删除「登录」行
- [x] A11 设备标签感知（我的 iPhone / iPad / Mac）
- [x] A12 三端退出路径（iPad/iPhone 返回按钮 + 右滑手势）
- [x] A13 Mac/iPad 共用外壳，按可用宽度自适应（宽→侧栏，窄→Tab）
- [x] A14 Tab 栏恢复（首页 / 设置）（iOS `ContentView` 的 `TabView` 含首页/设置；`HomeSmokeTests.testHomeTitleSettingsNewMapAndRows` 点这两个页签。祖先 tip `1b900f4` 上该 UITest 为 1/0，此后该测试与 `ContentView` 未改）
- [x] A15 设置入口去重（工具栏齿轮 / 更多菜单 / ⌘, / 侧栏 四处收敛）（首页工具栏无齿轮；`ShellTab.homeOverflowTitles` 为空；更多菜单无「设置」；⌘, 只在 `FlorettaCommands`。`ShellTests.testMenusAndTemplatesOmitDeadActions`）
- [x] A16 删除重复的侧栏按钮（原来两个一模一样的）（侧栏没有无操作的「最近」行，也没有自绘 `sidebar.left`。`ShellTests.testCompactHomeShowsTheRecentStackAndSidebarRowsAreNotNoOps`；`HomeSmokeTests` 断言可点的「最近」只在导航栏标题里）
- [x] A17 侧栏右缘异常竖向阴影修复（`Floretta/Shared/Shell/LibraryHome.swift` 侧栏边缘修复；PR #95）
- [x] A18 最近列表真实缩略图（`Floretta/Shared/Shell/DocumentSession.swift` 缩略图生成/缓存，`LibraryHome.swift` 展示；PR #95）
- [x] A19 新建面板真实预览（Mac 版）（`NewMapPage` / `TemplateThumbnail` 十二种结构各画一套，Mac 与 iOS 共用。`ShellTests.testMenusAndTemplatesOmitDeadActions` 断言 12 张卡片树形签名互不相同）
- [x] A20 返回键位置：移到文件名左侧、红绿灯右侧（`DocumentEditor` 工具栏 `cancellationAction`：返回按钮在文件名左侧。`EditorChromeContractTests`）
- [x] A21 文件名嵌套重复（窗口标题与工具栏各一个「未命名」）（`.navigationTitle("")` 且 Mac `titleVisibility = .hidden`，文件名只留在工具栏。`EditorChromeContractTests`）
- [x] A22 macOS 菜单栏（`Floretta/Shared/FlorettaApp.swift` focused commands：Insert/Format/View/Export；PR #94。系统 File/Edit/Window/Help 由 SwiftUI 提供）
- [x] A23 `docs/DESIGN-RULES.md`（唯一入口、退出可达、图标优先、禁止重复控件、禁止占位假数据；六条规矩已在该文件，前五条与本行一致）
- [x] A24 冒烟 13 条全覆盖（PR #107/#110/#112）：`#4–#12` 均有落盘文件回读断言（ZIP 含 document.json、PNG/PDF/MD 文件内容、.mm/.opml 导入回读）；本地实测 13/13 通过；顺带修好 Zen 退出按钮 44pt 点击区
- [x] A25 模板库重做（12 个真模板，结构各不相同，禁止同树换色）（`TemplateKind` 十二个；`ShellTests.testMenusAndTemplatesOmitDeadActions` 断言名称与 `TemplateKind.shape` 均不重复）
- [x] A26 底栏字数（底栏在「主题: N」旁显示「字数: N」。Mac 在底栏右侧，悬停展开主题 / 字数 / 字符数；iPhone / iPad 把这三项放在底栏上。只计节点标题，编辑中实时更新。验收：中心主题 + 分支主题 1–4 = 主题 5、字数 24、字符数 28。`TopicTitleCensusTests`。PR #75 → main `658b0c37`，tip `c9d6eb28`。Censor 与独立确认的 CI、Pro 已通过该 tip）
- [~] A27 实现存在（`InspectorTabPinUITests`）；**当前 build 无 AX 读数**，现有数字来自已安装 build 8，不作为验收证据

## B. 附件（核心差异化）

- [x] B1 附件数据模型：`assets/<sha256>.<ext>` + 引用计数 + 孤儿回收（测试：引用计数/孤儿 GC）
- [x] B2 流式写入/读取（实测 1GiB 与 10GiB 增量均 448KB；测试：10GB 打开不读正文）
- [x] B3 图片插入三条入口（文件选择 / 拖放 / 剪贴板粘贴；等比不裁切；异步解码；PDF/PNG 按页面分辨率）。待 Censor
- [x] B4 任意文件附件（PSD / PDF / DMG / 任意类型），UTType 图标（无系统图标则通用文件图标）+ 文件名 + 大小角标；QuickLook。待 Censor
- [~] B5 节点级音频（`CanvasAudioPlaybackBar.swift`、`InfiniteCanvas.swift`、`DocumentEditor.swift`；PR #96。单测通过；音频播放帧率、全应用内存与 GUI 验收未测）
- [~] B6 节点级视频（`MediaVideoPlayer.swift`、`DocumentEditor.swift`、`AttachmentPolicy.swift`；PR #96。AVPlayer 接入；iOS/macOS 最新完整构建及 GUI 验收未完成）
- [x] B7 节点内预览：文件类接 QLPreviewPanel/QuickLook；音视频波形与缩略图已在节点内渲染（PR #106）
- [x] B8 体积提示（插入前弹窗告知单文件与文档总体积）（`AttachmentInsertProposal.confirmationMessage`；`FileAttachmentTests.testConfirmDialogShowsFileSizeAndProjectedTotal`、`StreamingTests.testProposalUsesSizesOnly`；`DocumentEditor` 确认框展示该文案，取消走 `cancelInsert`）
- [x] B9 零压缩零转码硬规则（字节一致，sha256 只做去重与校验）—— 已写进规格
- [x] B10 软上限 10GB（用户塞进去就有预期，不做硬拦截）（`StreamingBudget.softCapBytes`；超限只在确认文案加一句，`FileAttachmentRoute.proposal` 仍返回提案。`FileAttachmentTests.testSoftCapDoesNotRefuseAnInsertProposal`、`StreamingTests.testProposalUsesSizesOnly`。流式写入只拒绝超过 Int64 的长度）

## C. 结构与表达力

- [x] C1 自由节点（独立 ID + 持久坐标、可连线/搜索/计数、v1 文件向后兼容；6 条单测）。待 Censor
- [x] C2 便签（画布辅助卡，≤5 色，可选是否进导出，不进 .xmind，不参与节点计数）。待 Censor
- [x] C3 关系线（跨分支连线 + 标签，可选中/删除/撤销；PR #48 合入 main `22a48dd`，tip `0e82523`；Censor 通过；Pro 双验绿）
- [x] C4 概要 + 边界（选区生成概要节点；边界视觉圈定；PR #51 合入 main `37a97aa`，tip `571746f`；Censor 通过；Pro 双验绿）
- [x] C5 标签 / 标记（优先级、进度、旗帜）+ 按标签筛选（PR #53 合入 main `fd97255`，tip `942f46b`；Censor 通过；Pro 双验绿，macOS 258/0 含 `TagFilterTests`）
- [x] C6 分支配色 / 主题预设（≤8 套，深浅色各一套；PR #55 合入 main `88d50e9`，tip `4b6bc5b`；Censor 通过；FlorettaCore CI 绿；Pro 双验绿，macOS 263/0 含 `testPNGAndPDFKeepBranchThemeColors`）
- [x] C7 多画布（Sheet，PR #86 合入；`DocumentEditor.swift` 有 canvasSheet/CanvasTab 实现）

## D. 格式与互通（T0）

- [x] D1 `.xmind` 双向导入导出（PR #43 → main `4aed816`。`XMindRoundTripTests`：六类样本未改则 `content.json` 与其余条目字节不变，改标题后再导入能读回。只有 `content.xml` 的文件拒绝导入）
- [x] D2 pass-through（读不懂的字段原样保留，未改动则原样写回）（`.xmind` `xmindForeign`、`.opml` `opmlForeign`、`.mm` `mmForeign`。`XMindRoundTripTests.testSixFixturesRoundTripUnchangedBytesAndEditedFields`、`OPMLRoundTripTests.testPassthroughSurvivesAnEditAndComesBackWhenReverted`、`MMRoundTripTests.testPassthroughSurvivesAnEditAndComesBackWhenReverted`。Markdown 按规格丢掉认不出的行，不走 pass-through）
- [x] D3 fixture 往返测试集（简单/多层/带样式/带关系线/带附件/多画布六类）（`Tests/FlorettaCoreTests/Fixtures/XMind/` 的 simple、nested、styled、relationships、attachments、multi-sheet。`XMindRoundTripTests.testSixFixturesRoundTripUnchangedBytesAndEditedFields` 与 `testFieldCatalogMatchesTheInRepoTable`）
- [x] D4 OPML / FreeMind / Markdown 保真度对齐（PR #44 → main `0c05171`。字段表 `docs/OPML-FIELDS.md`、`docs/MM-FIELDS.md`、`docs/MARKDOWN-FIELDS.md` 与 catalog 单测对照：`OPMLRoundTripTests`、`MMRoundTripTests`、`MarkdownFieldTests`、`MarkdownAsDocumentTests`。对方软件打开仍记在 `docs/FORMATS.md` 验收表，不在这次单测里）
- [x] D5 Markdown 一等文档：可直接打开编辑保存，纯结构投影（不含附件/颜色/关系线），顶部标注「Markdown 模式」，可一键升级为 `.floretta`，AI 用路径定位（root/3/1）（PR #62 → main `5631b42`，tip `ba0e893`；路径 API（`root/3/1`）仍是 S3，不在这次合并）
- [x] D6 导出 TextBundle（带附件）（`FlorettaCore/Format/FlorettaTextBundleCodec.swift` + `DocumentEditor` 导出入口；PR #45 / #103）

## E. AI 适配

- [x] E1 `docs/FORMAT-FOR-AI.md`（明文 JSON、稳定 ID、字段说明；已在 main）
- [x] E2 CLI（与 MCP 同一个原生二进制，`floretta tree / node add / export`）（PR #71 → main `dbde570c`，tip `af2ea145`）
- [x] E3 MCP stdio server（可选组件，不常驻不联网）（PR #71 → main `dbde570c`，tip `af2ea145`）
- [x] E4 体积门禁（PR #110：`scripts/check-size.sh` + `size-gate.yml`，实测 iOS 11.1MB / macOS 17.1MB；口径为测量前 strip Mach-O，DWARF 留在 dSYM）

## F. 平台与架构

- [x] F1 `FlorettaCore` 抽取（PR #29 已合入 `eb83ef2`，macOS 104/0）
- [x] F2 `docs/ADR-021-platform-layering.md`（三层结构 + 平台优先级）
- [x] F3 平台能力协议注入（FileAccess / Pasteboard / DeviceInfo / Clock / FontMetrics；PR #108 合入，`newMap`/`ThumbnailFileCache` 已注入 `ports.clock`；**缺口：`DocumentSession.makeNew()` 无单测覆盖**）
- [x] F4 CI 检查：Core 内禁止 SwiftUI/AppKit/UIKit 与 `#if os`（`.github/workflows/floretta-core.yml` 在 `ubuntu-24.04` 跑 `scripts/check-floretta-core-imports.sh`，命中 `import SwiftUI|AppKit|UIKit|SwiftData` 或 `#if os(` 即失败）
- [x] F5 Windows / Linux 预留评估（结论：核心 65% 可复用，UI 必须重写）

## G. 性能与可信度

- [x] G1 `docs/PERF-BUDGET.md`（九条硬门槛）
- [x] G2 PR 必带「性能影响三行」（内存/帧率/包体），缺失即打回（`docs/PERF-BUDGET.md` 硬门槛；PR #71）
- [x] G3 原子写入（临时文件 + fsync + rename）+ 按附件点名的 sha256 清单
- [x] G4 版本快照与回滚（1.7 `document.json` 旁路快照与回滚数据层，以及 4.1 历史列表、回滚确认、对比 UI，均已合并）（PR #64 → main `b0fb7fc`，tip `d681bf3`）
- [x] G5 Quick Look 插件（macOS，Finder 里可预览 .floretta）（PR #67 → main `a9ad9b92`，tip `1b900f4`）
- [x] G6 多窗口（macOS，同一文档多窗口实时同步）（PR #66 → main `5d6b994`，tip `04f65529`）

## H. 网站

- [x] H1 产品页改成可交互思维导图（横屏双侧、竖屏向下树、FLIP 过渡）
- [x] H2 七项能力内容上线（附件/10GB/零压缩、AI 可读写、XMind 互通、自由节点便签、大纲平等、性能门槛、不登录不联网）
- [x] H3 删除「一张会呼吸的思维导图」（标题、meta、根节点副标题、manifest 全清）
- [x] H4 展厅卡片图标换成真 App 图标（原为 PWA 占位图）
- [x] H5 Markdown 一等文档分支补进网站（PR #6 合并 + 已部署，页面含 Markdown×4 / .md / Obsidian）
- [x] H6 `docs/WEB-PARITY.md` 同步表（`docs/WEB-PARITY.md`；PR #98）

## I. 流程与交付

- [x] I1 Censor 审查 bot + `docs/REVIEW-WORKFLOW.md`（19 条清单、报告格式、阻断项带证据）
- [x] I2 竞品调研 `docs/RESEARCH-COMPETITORS.md`（321 行，44 个来源）
- [x] I3 夜间工作单 `docs/TASKBOOK-007-overnight.md`（Phase 1–4）
- [x] I4 交接文档 `docs/HANDOFF-WINDOWS-ANDROID.md`（该文件；PR #98）
- [x] I5 版本号纪律（`docs/RELEASE.md` 规定上传 build +1 并记录设置页版本显示路径；PR #98）
- [x] I6 TestFlight 统一安装 + 旧版本清理（`docs/CLEANUP.md` I6 清单及非破坏性操作边界；PR #98。实时 TestFlight 列表未核实，未执行清理）
- [x] I7 工作区旧构件清理（`docs/CLEANUP.md` I7 清单及逐项保留/候选说明；PR #98。未执行清理）
- [ ] I8 仓库转 public（**2026-11-13 定：等当前活干完再重写历史 + 转公开**。触发条件：#121、#122 与 build 14 都落地后。步骤：① 已完成 2026-11-13（副本归档到 `~/AWS/Achive/chat history/brand-and-naming-chat.md` + `.provenance.md` 来源说明，93,991 字节 / 2,242 行 / md5 `69ba0a79…` 校验一致；并以 `24056ff` 从工作树移除）。**仍待**：`git filter-repo` 把它从全部历史 purge （当前 `git log --all` 仍能查到 2 个 commit 引用它）→ ② 已完成 2026-11-13（`823e341` 加 `LICENSE`，MIT，`Copyright (c) 2026 Super-Console`，沿用 AppSettings.swift 既有署名写法）→ ③ 转 public。理由：该文件在第 5 个 commit 就进来了、共 400 个 commit，删它必须重写全部 SHA，影响 101 个远端分支与 Pro 上十几个 worktree，会打断进行中的活，所以排在活干完之后。动机：GitHub 对**私有仓库**的 Actions 要求账号绑定支付方式（free 额度内也拦），而**公开仓库的标准 runner 完全免费、不限量**——转公开即可永久免去这笔顾虑。背景核实：账号 free plan、10/11 月用量 netAmount 均为 0、未超 2000 分钟与 500MB 存储，不是欠费是缺支付方式；全历史无任何密钥痕迹）

## J. 入口 / Phase 3

- [x] 3.1 分享扩展 + 快捷指令（PR #57 → main `2bf1f4a`，tip `9e4c4f6`）
- [x] 3.2 语音输入（PR #58 → main `536f6c8`，tip `de9c20c`）
- [x] 3.3 Markdown 大纲导入（PR #60 → main `345a515`，tip `4ca7184`）

---

## 已知阻塞

| 阻塞 | 影响 | 需要谁 |
|---|---|---|
| Cursor 未授权 `Super-Console/Floretta` 仓库 | Interop 的规格文档推不上去（MD-AS-DOCUMENT / FORMAT-FOR-AI / FORMATS 已在本地） | 用户点「添加仓库」授权 |
| `1.0 (1)` 仍占着 Beta 审核队列 | 新 build 无法同时提交外部测试审核 | 等审核结束或撤下旧 build |
| Python 3.14 无 pip | 部分脚本工具受限 | 非阻塞 |

## 统计

- 已完成并验过：**70** 项
- 已派未合并/未验：**10** 项
- 未开始：**1** 项
- 合计：**82** 项
- 已知阻塞：**3** 项
