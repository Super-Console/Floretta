# C7 多画布核实

## 结论

多画布入口、创建与切换均已实现；文档持久化也已由 Core 往返测试覆盖。依据仓库源码与测试，C7 的实现项可以判定完成；本次未在 macOS/iOS 图形会话中单独做人工验收。

## 证据

- 入口及创建：`Floretta/Shared/Shell/DocumentEditor.swift` 的 `canvasTabBar` 渲染 `canvas.tab.<index>` 标签和 `canvas.tab.add` 按钮；加号调用 `session.addCanvas(...)`。
- 切换：同文件 `canvasTab(_:)` 的点击调用 `session.activateCanvas(index, ...)`。
- 会话状态：`Floretta/Shared/Shell/DocumentSession.swift` 的 `addCanvas` / `activateCanvas` 更新 `MindMapDocument`，新画布在创建后成为活动画布。
- 持久化：`Tests/FlorettaCoreTests/CanvasSheetTests.swift` 中 `testSaveAndOpenKeepsEveryCanvasTheActiveTabAndZoom` 对 `FlorettaCodec.encode/decode` 往返断言画布数量、活动标签、名称、节点与视口；`testNativeSaveKeepsCanvasesAndSingleTreeExportsNameTheActiveOne` 覆盖 native 文档保留多画布。
- UI 可达性：新增 `HomeSmokeTests.testMultipleCanvasesCanBeAddedAndSwitched` 通过 accessibilityIdentifier 检查标签栏、添加入口以及两个画布之间切换。
- 测试实测：`swift test --filter CanvasSheetTests` 通过，7 项测试、0 失败；包括创建/活动画布、编码解码后保留多画布和当前页、native save 保留多画布。`scripts/pre-release.sh` 的 UI suite 8 项通过，其中新增 `testMultipleCanvasesCanBeAddedAndSwitched` 实测入口、新增与切换。

## 限制

持久化证据来自 Core 序列化/解码测试，不等同于一次手工文件保存后重新打开的端到端 UI 验收；本次也没有单独做手工图形验收。
