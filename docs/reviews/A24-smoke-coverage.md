# A24 — UI 冒烟覆盖核对

核对范围为 `docs/SMOKE.md` 前 13 条。自动化只证明标注为「已覆盖」的检查；不把菜单出现等同于操作成功，也不把模拟器测试等同于 macOS/iPad/iPhone 人工验收。

| # | 路径 | 当前自动化覆盖 |
|---|---|---|
| 1 | 启动 → 首页 | 已覆盖：首页标题、最近列表和设置入口。 |
| 2 | 新建导图 | 已覆盖：创建后进入编辑器并检查标题。 |
| 3 | 输入文字（含中文组字） | 部分：编辑态节点框几何测试，不验证键入或中文组字。 |
| 4 | 新建子节点 / 同级 | 已覆盖：`A24EditorActionSmokeTests.testSmoke4InsertChildAndSiblingEnableUndo`（`FlorettaUITests/HomeSmokeTests.swift:293`），通过 `smoke.insert.child` / `smoke.insert.sibling` 执行命令，并检查撤销变为可用。 |
| 5 | 删除节点 | 已覆盖：`A24EditorActionSmokeTests.testSmoke5DeleteSelectedTopicEnablesUndo`（同文件 `:313`），实际执行删除并检查撤销可用。 |
| 6 | 撤销 / 重做 | 已覆盖：`A24EditorActionSmokeTests.testSmoke6UndoThenRedoEnableOppositeActions`（同文件 `:330`），实际执行新增、撤销、重做并核对对应命令状态。 |
| 7 | 保存到文件 | 已覆盖路径：`A24EditorActionSmokeTests.testSmoke7SaveAsFlorettaPresentsSavePanel`（同文件 `:346`），执行「保存为 Floretta」并断言系统保存面板出现。未在面板里选定路径并回读文件。 |
| 8 | 从文件 App 再打开 | 已覆盖路径：`A24EditorActionSmokeTests.testSmoke8OpenFromFilesPresentsDocumentPicker`（同文件 `:358`），从首页打开「从文件应用打开」并断言系统文件选择器出现。未选中文件并核验打开内容。 |
| 9 | 导出 PNG / PDF / Markdown | 已覆盖路径：分别由 `testSmoke9ExportPNGShowsExportPicker`、`testSmoke9ExportPDFShowsExportPicker`、`testSmoke9ExportMarkdownShowsExportPicker`（同文件 `:371` / `:382` / `:393`）执行三种导出并断言系统保存面板出现。未保存并验证导出产物。 |
| 10 | 导入 `.mm` / `.opml` | 已覆盖路径：`A24EditorActionSmokeTests.testSmoke10ImportMMAndOPMLPresentDocumentPicker`（同文件 `:404`）。两种格式共用插入菜单的「从文件导入」（`smoke.import.file`）系统选择器；分享菜单里的 `.mm` / `OPML` 是导出命令。未在选择器里分别选中文件并核验画布内容。 |
| 11 | 退出 → 首页（Mac / iPad / iPhone） | 部分：iOS UI 测试验证返回首页；未分别覆盖 Mac 与 iPad。 |
| 12 | Zen 进入 / 退出 | 已覆盖：`A24EditorActionSmokeTests.testSmoke12ZenEnterAndExitRestoresToolbar`（同文件 `:417`），进入沉浸模式后退出，并断言工具栏与画布恢复。 |
| 13 | 画布 / 大纲切换 | 已覆盖：聚焦/画布切换及大纲开关。 |

A24 发布阻断的 8 条路径（`#4–#10`、`#12`）均已有可失败的 XCUITest；`#9` 拆成 PNG / PDF / Markdown 三条，避免首项失败后跳过其余导出。`#7–#10` 验证的是真实系统面板被打开，而不是选中文件后的内容回读。新增的多画布测试另行覆盖入口、新增与切换（见 `C7-multi-canvas-verification.md`），不计入以上 13 条。系统文件面板检测不主动激活 Files app，并同时接受应用内 sheet 与独立 DocumentManager / Files 进程，以免把切到 Files 本身当成验收，或把仍留在前台的 sheet 误判为失败。
