# A24 — UI 冒烟覆盖核对

核对范围为 `docs/SMOKE.md` 前 13 条。自动化只证明标注为「已覆盖」的检查；不把菜单出现等同于操作成功，也不把模拟器测试等同于 macOS/iPad/iPhone 人工验收。

| # | 路径 | 当前自动化覆盖 |
|---|---|---|
| 1 | 启动 → 首页 | 已覆盖：首页标题、最近列表和设置入口。 |
| 2 | 新建导图 | 已覆盖：创建后进入编辑器并检查标题。 |
| 3 | 输入文字（含中文组字） | 部分：编辑态节点框几何测试，不验证键入或中文组字。 |
| 4 | 新建子节点 / 同级 | 部分：`A24EditorActionSmokeTests.testSmoke4InsertChildAndSiblingEnableUndo`（`FlorettaUITests/HomeSmokeTests.swift:293`），通过 `smoke.insert.child` / `smoke.insert.sibling` 执行命令，并检查撤销变为可用；未核对画布节点文本/数量。 |
| 5 | 删除节点 | 部分：`A24EditorActionSmokeTests.testSmoke5DeleteSelectedTopicEnablesUndo`（同文件 `:312`），实际执行删除并检查撤销可用；未核对删除后的节点内容。 |
| 6 | 撤销 / 重做 | 部分：`A24EditorActionSmokeTests.testSmoke6UndoThenRedoEnableOppositeActions`（同文件 `:331`），实际执行新增、撤销、重做并核对对应命令状态。 |
| 7 | 保存到文件 | 未通过最近一次 UI 运行：`A24EditorActionSmokeTests.testSmoke7SaveAsFlorettaPresentsSavePanel`（同文件 `:349`）未能证明 Files 的 Browse View 已出现；未保存并回读文件。 |
| 8 | 从文件 App 再打开 | 未通过最近一次 UI 运行：`A24EditorActionSmokeTests.testSmoke8OpenFromFilesPresentsDocumentPicker`（同文件 `:361`）未能证明 Files 的 Browse View 已出现；未选中文件并核验打开内容。 |
| 9 | 导出 PNG / PDF / Markdown | 未通过最近一次 UI 运行：`A24EditorActionSmokeTests.testSmoke9ExportPNGPDFFAndMarkdownPresentExportPanel`（同文件 `:373`）未能证明 PNG 导出打开系统面板；该组合用例在首项失败后未验证 PDF / Markdown；未保存并验证导出产物。 |
| 10 | 导入 `.mm` / `.opml` | 未通过最近一次 UI 运行：`A24EditorActionSmokeTests.testSmoke10ImportMMAndOPMLPresentDocumentPicker`（同文件 `:386`）未能证明 Files 的 Browse View 已出现；未分别选择 `.mm` / `.opml` 文件并核验画布内容。 |
| 11 | 退出 → 首页（Mac / iPad / iPhone） | 部分：iOS UI 测试验证返回首页；未分别覆盖 Mac 与 iPad。 |
| 12 | Zen 进入 / 退出 | 未通过最近一次 UI 运行：`A24EditorActionSmokeTests.testSmoke12ZenEnterAndExitRestoresToolbar`（同文件 `:396`）进入 Zen 后点击退出，但旧断言检查关闭按钮消失失败；断言已改为检查工具栏恢复，尚未重跑。 |
| 13 | 画布 / 大纲切换 | 已覆盖：聚焦/画布切换及大纲开关。 |

最近一次 A24 UI 运行结果为 3/8 通过（#4–#6）；#7–#10 与 #12 未通过。系统文件面板检测现已调整为不主动激活 Files app，以免把切换到 Files 本身当成 picker 验收；上述修改尚未实测。新增的多画布测试另行覆盖入口、新增与切换（见 `C7-multi-canvas-verification.md`），不计入以上 13 条。文件导入、另存与导出仍需选择实际文件并验证内容，#4/#5 也需核对画布节点本身。当前仍未达到 A24 的 13 条完整覆盖验收，发布阻断保持有效。

最近一次 UI 测试执行结果为 3 项通过（#4–#6）、5 项失败（#7–#10、#12）。#7–#10 的断言错误地尝试激活 Files.app 来验证 picker；现已移除该激活行为，改为仅观察系统 picker，#12 改为断言退出 Zen 后工具栏恢复。上述修正尚未重新执行验证，不计为通过。
