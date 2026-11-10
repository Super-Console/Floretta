STATUS: DONE

已实现：macOS 编辑器窗口通过 SwiftUI focused commands 暴露现有插入、视图、格式配色/字体/字号/粗体/斜体、查找、快捷键一览/关于和 PNG/PDF/Markdown/Floretta/XMind 导出操作；节点可用状态按选择及可包围条件计算。系统提供的 File/Edit/Window/Help 基础命令保留，另加入系统 SidebarCommands。快捷键冲突与无选中节点禁用测试 3 项通过，并记录快捷键。

未加入：节点对齐没有对应节点属性/编辑控制；TextBundle core codec 虽可生成包数据，但编辑器文件导出流程未接通该包的保存形式，菜单无法提供有效的 TextBundle 导出，所以两项都不添加占位命令。

验证：`xcodebuild -list -project Floretta.xcodeproj` 成功；`swift test --filter MacMenuShortcutCatalogTests` 通过（3 项）；`git diff --check` 通过。指定 macOS build 在 Share 扩展 CodeSign 报 `errSecInternalComponent` 后停止，没有重试；编译验证需 GUI 会话复核。没有 plist 改动。
