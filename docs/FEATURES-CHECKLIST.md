# Floretta 功能检查单

会话：2026-11-09 ~ 11-10
图例：`[x]` 已完成并验过 · `[~]` 已派但未合并/未验 · `[ ]` 未开始

维护规则：状态变化就改这里，一行一项，不许合并行。每个功能合入必须在同一变更集或紧随其后的跟进里更新本清单，不能只改 `docs/STATUS.md`。

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
- [~] A14 Tab 栏恢复（首页 / 设置）
- [~] A15 设置入口去重（工具栏齿轮 / 更多菜单 / ⌘, / 侧栏 四处收敛）
- [~] A16 删除重复的侧栏按钮（原来两个一模一样的）
- [~] A17 侧栏右缘异常竖向阴影修复
- [~] A18 最近列表真实缩略图（当前是灰色占位）
- [~] A19 新建面板真实预览（Mac 版）
- [~] A20 返回键位置：移到文件名左侧、红绿灯右侧
- [~] A21 文件名嵌套重复（窗口标题与工具栏各一个「未命名」）
- [~] A22 macOS 菜单栏（文件/编辑/插入/格式/视图/导出/窗口/帮助，图标+文字+快捷键）
- [~] A23 `docs/DESIGN-RULES.md`（唯一入口、退出可达、图标优先、禁止重复控件、禁止占位假数据）
- [~] A24 `docs/SMOKE.md` + XCUITest 冒烟（13 条可达性路径，打包前必跑）
- [~] A25 模板库重做（12 个真模板，结构各不相同，禁止同树换色）

## B. 附件（核心差异化）

- [x] B1 附件数据模型：`assets/<sha256>.<ext>` + 引用计数 + 孤儿回收（测试：引用计数/孤儿 GC）
- [x] B2 流式写入/读取（实测 1GiB 与 10GiB 增量均 448KB；测试：10GB 打开不读正文）
- [x] B3 图片插入三条入口（文件选择 / 拖放 / 剪贴板粘贴；等比不裁切；异步解码；PDF/PNG 按页面分辨率）。待 Censor
- [x] B4 任意文件附件（PSD / PDF / DMG / 任意类型），UTType 图标（无系统图标则通用文件图标）+ 文件名 + 大小角标；QuickLook。待 Censor
- [~] B5 节点级音频（插入已有音频 + 播放条，不做录音机）
- [~] B6 节点级视频（插入 + 播放）
- [~] B7 节点内预览：文件类已接 QLPreviewPanel/QuickLook；音频视频待 1.5 之后
- [~] B8 体积提示（插入前弹窗告知单文件与文档总体积）
- [x] B9 零压缩零转码硬规则（字节一致，sha256 只做去重与校验）—— 已写进规格
- [~] B10 软上限 10GB（用户塞进去就有预期，不做硬拦截）

## C. 结构与表达力

- [x] C1 自由节点（独立 ID + 持久坐标、可连线/搜索/计数、v1 文件向后兼容；6 条单测）。待 Censor
- [x] C2 便签（画布辅助卡，≤5 色，可选是否进导出，不进 .xmind，不参与节点计数）。待 Censor
- [x] C3 关系线（跨分支连线 + 标签，可选中/删除/撤销；PR #48 合入 main `22a48dd`，tip `0e82523`；Censor 通过；Pro 双验绿）
- [x] C4 概要 + 边界（选区生成概要节点；边界视觉圈定；PR #51 合入 main `37a97aa`，tip `571746f`；Censor 通过；Pro 双验绿）
- [x] C5 标签 / 标记（优先级、进度、旗帜）+ 按标签筛选（PR #53 合入 main `fd97255`，tip `942f46b`；Censor 通过；Pro 双验绿，macOS 258/0 含 `TagFilterTests`）
- [x] C6 分支配色 / 主题预设（≤8 套，深浅色各一套；PR #55 合入 main `88d50e9`，tip `4b6bc5b`；Censor 通过；FlorettaCore CI 绿；Pro 双验绿，macOS 263/0 含 `testPNGAndPDFKeepBranchThemeColors`）
- [~] C7 多画布（Sheet）

## D. 格式与互通（T0）

- [~] D1 `.xmind` 双向导入导出
- [~] D2 pass-through（读不懂的字段原样保留，未改动则原样写回）
- [~] D3 fixture 往返测试集（简单/多层/带样式/带关系线/带附件/多画布六类）
- [~] D4 OPML / FreeMind / Markdown 保真度对齐
- [~] D5 Markdown 一等文档：可直接打开编辑保存，纯结构投影（不含附件/颜色/关系线），顶部标注「Markdown 模式」，可一键升级为 `.floretta`，AI 用路径定位（root/3/1）（S2 UI 为 PR #62，未合并未验；路径 API 仍是 S3）
- [ ] D6 导出 TextBundle（带附件，便于带走）

## E. AI 适配

- [~] E1 `docs/FORMAT-FOR-AI.md`（明文 JSON、稳定 ID、字段说明）
- [ ] E2 CLI（与 MCP 同一个原生二进制，`floretta tree / node add / export`）
- [ ] E3 MCP stdio server（可选组件，不常驻不联网）
- [ ] E4 体积约束：禁止引入 Node/Python 运行时；增量控制在一两 MB

## F. 平台与架构

- [x] F1 `FlorettaCore` 抽取（PR #29 已合入 `eb83ef2`，macOS 104/0）
- [x] F2 `docs/ADR-021-platform-layering.md`（三层结构 + 平台优先级）
- [~] F3 平台能力协议注入（FileAccess / Pasteboard / DeviceInfo / Clock / FontMetrics）
- [~] F4 CI 检查：Core 内禁止 SwiftUI/AppKit/UIKit 与 `#if os`
- [x] F5 Windows / Linux 预留评估（结论：核心 65% 可复用，UI 必须重写）

## G. 性能与可信度

- [x] G1 `docs/PERF-BUDGET.md`（九条硬门槛）
- [~] G2 PR 必带「性能影响三行」（内存/帧率/包体），缺失即打回
- [x] G3 原子写入（临时文件 + fsync + rename）+ 按附件点名的 sha256 清单
- [~] G4 版本快照与回滚（`document.json` 旁路快照、可回滚；历史列表 UI 仍是 4.1）
- [ ] G5 Quick Look 插件（macOS，Finder 里可预览 .floretta）
- [ ] G6 多窗口（macOS，同一文档多窗口实时同步）

## H. 网站

- [x] H1 产品页改成可交互思维导图（横屏双侧、竖屏向下树、FLIP 过渡）
- [x] H2 七项能力内容上线（附件/10GB/零压缩、AI 可读写、XMind 互通、自由节点便签、大纲平等、性能门槛、不登录不联网）
- [x] H3 删除「一张会呼吸的思维导图」（标题、meta、根节点副标题、manifest 全清）
- [x] H4 展厅卡片图标换成真 App 图标（原为 PWA 占位图）
- [x] H5 Markdown 一等文档分支补进网站（PR #6 合并 + 已部署，页面含 Markdown×4 / .md / Obsidian）
- [~] H6 `docs/WEB-PARITY.md` 同步表（Mac 功能 ↔ 网页状态）

## I. 流程与交付

- [x] I1 Censor 审查 bot + `docs/REVIEW-WORKFLOW.md`（19 条清单、报告格式、阻断项带证据）
- [x] I2 竞品调研 `docs/RESEARCH-COMPETITORS.md`（321 行，44 个来源）
- [x] I3 夜间工作单 `docs/TASKBOOK-007-overnight.md`（Phase 1–4）
- [~] I4 交接文档 `docs/HANDOFF-WINDOWS-ANDROID.md`
- [ ] I5 版本号纪律（每次上传 build +1；设置页显示版本）
- [ ] I6 TestFlight 统一安装 + 旧版本清理（只移废纸篓，先列清单）
- [ ] I7 工作区旧构件清理（build/archive/DerivedData，先列清单再动）
- [ ] I8 仓库转 public（已暂缓；前置：LICENSE、私人对话文件 `docs/design/brand-and-naming-chat.md` 需移出历史）

## J. 入口 / Phase 3

- [~] 3.1 分享扩展 + 快捷指令（PR #57 已开，未合入 main）
- [~] 3.2 语音输入（PR #58 已开，未合入 main）
- [~] 3.3 Markdown 大纲导入（实现进行中，尚无 PR）

---

## 已知阻塞

| 阻塞 | 影响 | 需要谁 |
|---|---|---|
| Cursor 未授权 `Super-Console/Floretta` 仓库 | Interop 的规格文档推不上去（MD-AS-DOCUMENT / FORMAT-FOR-AI / FORMATS 已在本地） | 用户点「添加仓库」授权 |
| `1.0 (1)` 仍占着 Beta 审核队列 | 新 build 无法同时提交外部测试审核 | 等审核结束或撤下旧 build |
| Python 3.14 无 pip | 部分脚本工具受限 | 非阻塞 |

## 统计

- 已完成并验过：**37** 项
- 已派未合并/未验：**32** 项
- 未开始：**11** 项
- 合计：**80** 项
- 已知阻塞：**3** 项
