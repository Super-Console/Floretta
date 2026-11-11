# A24 — UI 冒烟覆盖核对

核对范围为 `docs/SMOKE.md` 前 13 条。自动化只证明标注为「已覆盖」的检查；不把菜单出现等同于操作成功，也不把模拟器测试等同于 macOS/iPad/iPhone 人工验收。

| # | 路径 | 当前自动化覆盖 |
|---|---|---|
| 1 | 启动 → 首页 | 已覆盖：首页标题、最近列表和设置入口。 |
| 2 | 新建导图 | 已覆盖：创建后进入编辑器并检查标题。 |
| 3 | 输入文字（含中文组字） | 部分：编辑态节点框几何测试，不验证键入或中文组字。 |
| 4 | 新建子节点 / 同级 | 已覆盖：`A24EditorActionSmokeTests.testSmoke4InsertChildAndSiblingEnableUndo`（`FlorettaUITests/HomeSmokeTests.swift`），通过 `smoke.insert.child` / `smoke.insert.sibling` 执行命令，并检查撤销变为可用。 |
| 5 | 删除节点 | 已覆盖：`A24EditorActionSmokeTests.testSmoke5DeleteSelectedTopicEnablesUndo`（同文件），实际执行删除并检查撤销可用。 |
| 6 | 撤销 / 重做 | 已覆盖：`A24EditorActionSmokeTests.testSmoke6UndoThenRedoEnableOppositeActions`（同文件），实际执行新增、撤销、重做并核对对应命令状态。 |
| 7 | 保存到文件 | 已覆盖：`A24EditorActionSmokeTests.testSmoke7SaveAsFlorettaWritesReadablePackage`。执行分享菜单「保存为 Floretta」后读取 `$FLORETTA_UITEST_DIR/export/未命名.floretta`，断言文件存在、非空、是含 `document.json` 的 ZIP，并含「中心」和新建子节点「新主题」。 |
| 8 | 从文件 App 再打开 | 已覆盖：`testSmoke8OpenFlorettaReadsDocument`、`testSmoke8OpenMMReadsMapNotMarkdown`、`testSmoke8OpenOPMLReadsMapNotMarkdown`。先回读夹具 `$FLORETTA_UITEST_DIR/import/A24-floretta-fixture.floretta`、`A24-mm-fixture.mm`、`A24-opml-fixture.opml`，再通过首页「打开」→「从文件应用打开」载入；断言文档标题来自文件内容（分别为「A24八Floretta」「A24八MM中心」「A24十OPML」），且没有 `markdown.mode.banner`。 |
| 9 | 导出 PNG / PDF / Markdown | 已覆盖：`testSmoke9ExportPNGWritesPNGFile` 读取 `$FLORETTA_UITEST_DIR/export/未命名.png` 并断言 PNG 签名；`testSmoke9ExportPDFWritesPDFFile` 读取 `未命名.pdf` 并断言 `%PDF` 头；`testSmoke9ExportMarkdownWritesMarkdownFile` 读取 `未命名.md`，断言 UTF-8 文本含 `# 中心` 与「新主题」。 |
| 10 | 导入 `.mm` / `.opml` | 已覆盖：`testSmoke10ImportMMReadsMapContent`、`testSmoke10ImportOPMLReadsMapContent`。先回读 `$FLORETTA_UITEST_DIR/import/A24-mm-fixture.mm` 与 `A24-opml-fixture.opml`（分别含 `<map>` / `<opml>` 及预期节点文本），再通过插入菜单「从文件导入」（`smoke.import.file`）打开；断言文档标题为「A24八MM中心」或「A24十OPML」，且没有被当成 Markdown。分享菜单里的 `.mm` / `OPML` 仍是导出命令，不是本条。 |
| 11 | 退出 → 首页（Mac / iPad / iPhone） | 部分：iOS UI 测试验证返回首页；未分别覆盖 Mac 与 iPad。 |
| 12 | Zen 进入 / 退出 | 已覆盖：`A24EditorActionSmokeTests.testSmoke12ZenEnterAndExitRestoresToolbar`（同文件），进入沉浸模式后退出，并断言工具栏与画布恢复。 |
| 13 | 画布 / 大纲切换 | 已覆盖：聚焦/画布切换及大纲开关。 |

A24 发布阻断的 8 条路径（`#4–#10`、`#12`）均已有可失败的 XCUITest；`#7–#10` 在操作后读取落盘文件并断言内容，不再用系统面板出现代替结果。`#9` 拆成 PNG / PDF / Markdown 三条，避免首项失败后跳过其余导出。新增的多画布测试另行覆盖入口、新增与切换（见 `C7-multi-canvas-verification.md`），不计入以上 13 条。UI 测试在 `-FlorettaUITest` 下通过 `FLORETTA_UITEST_DIR` / `FLORETTA_UITEST_IMPORT_FILE` 走同一套导出与打开管线，把文件写到可回读目录，而不把系统文件面板本身当作验收。
