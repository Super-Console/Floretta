# Zen 退出入口修复

- 修改：`DocumentEditor` 在 `session.zen.isActive` 时显示系统 `.borderedProminent` 按钮，保留 `zen.exit` identifier 并调用 `exitZen()`；未改测试断言。
- 验证：目标 UI 冒烟通过（`TEST SUCCEEDED`）；iOS unsigned build 成功。`FlorettaTests` 与 macOS build 被 macOS Share 扩展签名失败 `errSecInternalComponent` 阻塞，未改钥匙串。UI 视觉待 CUA；未运行完整 pre-release。
