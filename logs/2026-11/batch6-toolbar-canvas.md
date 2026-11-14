# 第六批：工具栏、菜单与多画布

- 日期：2026-11-15
- 基线：`0fab6a0`
- 分支：`feat/toolbar-canvas`
- 提交：B4、B6、D5 各一个独立 commit。

## 变更

- B4：保持 `.toolbar(id:)` 原生 customization，将工具栏缩放按钮改为 icon-only，并给 toolbar item 显式设置 accessibility label；新增合同测试。
- B6：原生菜单行采用 `Label`，为既有快捷键绑定 `.keyboardShortcut`；新增长菜单合同测试。
- D5：既有多画布模型和单画布兼容编码保留；新增画布删除、主画布提升逻辑、标签原生上下文菜单与会话操作；中英文文案同步更新。

## 验证与限制

- `swift test --package-path FlorettaCore`：391 tests，1 skipped，0 failures。
- `CanvasSheetTests`：9 tests，0 failures；包括添加、删除、切换索引、多画布保存和旧单画布文件兼容。
- `MacMenuShortcutCatalogTests`：5 tests，0 failures；`EditorToolbarCatalogTests`：7 tests，0 failures。
- macOS `xcodebuild build` 尝试到扩展签名阶段失败：`FlorettaShare-macOS` / `FlorettaQuickLookThumbnail-macOS` 的 `codesign` 返回 `errSecInternalComponent`，即使命令传入 `CODE_SIGNING_ALLOWED=NO`。遵守项目约定，没有尝试规避钥匙串。
- iOS build 与指定的 `FlorettaTests` 因签名阻塞未运行。GUI 验收/pre-release未运行。
- Xcode settings 回读：macOS `SDKROOT=MacOSX27.2.sdk`；iOS `SDKROOT=iPhoneSimulator27.2.sdk`。项目版本仍为 `1.0` / `17`，体积预算未改。
- 没有启动模拟器；检查时 booted 数量为 `1`，来源未知，未关闭。构建生成的 `/tmp/dd-batch6` 尚待用户同意清理。
- 已 push 至 `origin/feat/toolbar-canvas`，draft PR #19 已创建；由于 GUI 签名构建与指定 macOS 测试未通过/未运行，PR 标注为不可合并。

## 旧文件兼容性

单画布旧 `.floretta` 继续用 formatVersion 1 解析，缺失多画布键时默认为一张画布；只有多画布相关字段非默认时才编码。测试确认旧 JSON 解码、单画布状态和再次编码都成立。
