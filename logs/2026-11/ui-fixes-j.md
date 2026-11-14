# UI fixes J1–J4

- 日期：2026-11-15
- 影响：Floretta 的缩放、外观设置、编辑器标题栏/返回操作、侧边栏选中样式。
- 改动：J1–J4 分项提交；J5 仅记录三个待确认布局候选，没有改布局。
- 提交：`2100095`, `1247713`, `a82a3c3`, `33cacb3`, `48c75b4`；均已推送到 `fix/ui-fixes-j`。J2 有单独编译修正提交，未重写历史。
- 验证：macOS 与 iOS generic build 均 `BUILD SUCCEEDED`；FlorettaCore 380 tests、1 skipped、0 failures。截图 UI 测试未实跑，依赖 screenshot poller 与副屏 GUI 环境。
- 状态：PR #14 已创建且未合并；GUI UI 测试仍待运行。
