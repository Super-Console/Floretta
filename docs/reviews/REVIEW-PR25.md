# REVIEW-PR25

审查对象：PR #25 / commit `67fd3784b64f25a347315cffde5a52d7a7fccb8e` / build **1.0 (5)**（`CURRENT_PROJECT_VERSION = 5`）
审查时间：2026-11-10（Asia/Shanghai）
结论：**阻断**

对照：`docs/REVIEW-WORKFLOW.md`（main）、`docs/SMOKE.md`（本 PR 新增）。`docs/DESIGN-RULES.md` **不存在**（main 与 PR 头均无此文件）。

## 阻断项（必须修，不修不许发）

1. **[表达规范]** 编辑器顶栏仍是纯文字按钮，违反清单第 5 条。  
   证据：`Floretta/Shared/Shell/DocumentEditor.swift` 工具栏 `Button("撤销")` / `Button("重做")` / `Button("删除")`；`insertMenu` / `shareMenu` / `moreMenu` 的 label 为 `Text("插入")` / `Text("分享")` / `Text("更多")`。  
   修复要求：操作控件改为 SF Symbols 图标（可保留中文 `accessibilityLabel` / help）；禁止顶栏主操作以纯文字按钮呈现。

2. **[内容真实性]** 模板库 24 张里 18 张仍是同一棵思维导图树换色，违反清单第 8、9 条。  
   证据：`Floretta/Shared/Shell/DocumentSession.swift` 中 `TemplateCatalog.sections`：基本 6 + 知识管理 6 + 会议和计划 6 + 学习和教育 6 = 24；后三组均 `tap: .comingSoon`。`Floretta/Shared/Shell/TemplateThumbnail.swift` 中除基本 6 个 `switch` 分支外，`default` 一律走 `mindMapColored(...)`（仅 `palette(for:)` 换色）。  
   修复要求：砍到确有结构差异的模板，或为每张提供不可互换的缩略图结构；禁止「同一拓扑 + 换 palette」冒充 18 个模板。

3. **[视觉一致性]** 模板缩略图写死白/黑，深色模式刺眼，违反清单第 11 条。  
   证据：`Floretta/Shared/Shell/TemplateThumbnail.swift` — `background` 对非特例 `return .white`；`pill(..., fill: .white, ink: .black, ...)`；`BraceShape` / timeline 使用 `Color.black.opacity(...)`；全程无 `colorScheme` / semantic color。  
   修复要求：卡片底与描边改为自适应色（如 `.background` / `.primary` 或按 `colorScheme` 分支），深浅色都不得出现大片死白卡片。

4. **[可达性 / 表达规范]** Mac 首页「设置」与「侧栏」控件重复，违反清单第 3、7 条。  
   证据：  
   - 设置三入口仍在：`ContentView.swift` Mac `NavigationSplitView` 侧栏 `ShellTab.settings`；`LibraryHome.swift` `RecentPage` 工具栏 `gearshape` → `showSettings`；`FlorettaApp.swift` `CommandGroup(replacing: .appSettings)` + ⌘,。  
   - 侧栏开关：`RecentPage` 自绘 `sidebar.left` 切换 `columnVisibility`，与 Mac `NavigationSplitView` 系统侧栏控件叠在同一首页工具区。  
   修复要求：设置可见入口只保留侧栏（或 Tab）一处，⌘, 可保留；侧栏显隐只保留系统或自绘其一，去掉重复按钮。

5. **[性能与体积]** 缩放后画布文字与编辑态不一致，缩小时易糊成一团，违反清单第 15 条。  
   证据：`Floretta/Shared/Canvas/InfiniteCanvas.swift` — `styledText` 使用固定 `node.fontSize` 画进已按 `camera.viewport.scale` 变换的 `viewRect`；同文件 `editField` 却用 `frame.fontSize * max(camera.viewport.scale, 1)`。缩小后文字相对节点过大、挤叠。  
   修复要求：Canvas 绘制字号与编辑态同一套缩放公式；在 50% 与 400% 下文字可读、不重叠。`docs/SMOKE.md` 相关行仍为「未通」，修完须真机点证。

## 建议项（可记 backlog，不阻本轮）

- 侧栏右缘竖向阴影：本轮在 PR 头 Swift 源码中未定位到显式「右缘竖条 shadow」实现；若仍复现，请附截图与视图层级，再单开项。  
- `docs/SMOKE.md` 13 条全部「未通」：云端无 GUI，不能当已验收。  
- `docs/DESIGN-RULES.md` 缺失：请产品/文档侧补建，审查清单已引用设计规范却无落点。

## 已确认合格项（相对 main / 用户原报）

- **文档退出路径（代码层）**：main 上编辑器不在 `NavigationStack` 内；本 PR `ContentView.swift` 用 `NavigationStack { DocumentEditor(...) }`，且 `DocumentEditor` 工具栏有 `chevron.backward` → `onClose`。代码路径已接上；真机 SMOKE #11 仍「未通」。  
- **编辑提交后再撤销/删除**：`EditorSession.finishEditingIfNeeded` + `ShellTests.testUndoAndDeleteWorkWhileTheNewNodeIsStillBeingEdited`。  
- **二次点选进入编辑**：`NodeEditTap` + 双击开始编辑；单测 `testSecondTapOnTheSelectedNodeStartsEditing`。  
- **「更多」里去掉「更多设置」**：`CanvasMenus.more` 不再含「更多设置」；编辑器 sheet 设置入口已删。  
- **iOS Tab / Mac 侧栏出现「设置」目的地**：`ShellTab.destinations`；相对用户原报「侧栏没有设置」有改进，但与顶栏齿轮叠加，见阻断项 4。

## 复审条件

- 阻断项对应 commit 变更后通知 Censor「已修复 + commit/PR 号」。  
- 复审绑定新 commit hash；通过后回复「通过，可上传」。  
- Censor 不改业务代码、不合并 PR、不打包上传。
