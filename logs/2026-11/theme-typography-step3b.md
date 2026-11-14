# 主题字体接入页面文字

- 完成共享主题字体 modifier：按界面语言解析脚本，并逐个检查系统字体候选可用性。
- 接入首页/最近列表、设置及检查器、画布节点文字、状态栏和编辑器/工具栏文字。
- 修复 `ThemeSettings.swift` 在 Xcode project 中指向错误物理目录的问题。
- 新增 classic/Songti 与 modern/PingFang 两条解析测试。
- 验证：`swift test --package-path FlorettaCore` 共 386 项，1 skipped，0 failures；macOS 与 iOS build 均在签名阶段因 `errSecInternalComponent` 失败，详见 `DONE-theme-step3b.md`。
