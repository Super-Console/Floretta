# 补做：跑探针 + 提交（上一轮漏了）

你的报告说「未运行本轮 Release 探针」。**那个阻塞不成立**：探针不需要 Cua Driver，也不需要启动已安装的 App。

## 怎么跑（上一轮二分排查就是这么做的，脚本还在）
参考 `/tmp/ablate_run.py`（Pro 上已有）：
- Release 构建产物里的**可执行文件直接启动**，不走 `/Applications`、不按 bundle id
- `launchctl bootstrap gui/501 <plist>` 把进程挂到 GUI 会话里
- 参数：`-FlorettaKeyLatency 30 -FlorettaKeyLatencyNodes 12`
- 窗口移到副屏
- 每组至少 90 次采样，跑 2–3 次取中位数

## 要测什么
- **改后**（当前工作树）：Tab / Return / 方向键 的 p50
- 已知基线（同口径）：Tab 177.5 / Return 179.1 / 方向键 145.7 ms
- 达标线：方向键 p50 < 40 ms，Tab/Return p50 < 100 ms

## 然后
1. 把实测数字填回 `logs/2026-11/toolbar-isolate.md`，替换掉「未测」那三格。
2. `git add -A && git commit`（一条提交，message 说明「隔离 SwiftUI 工具栏出按键失效的视图树」+ 实测数字）。
3. **不 push、不合并**。
4. 数据不达标就如实写数字，不要调测量方法、不要挑有利组。

## 不要做
- 不截图、不动 `/Applications`、不 kill 别人的进程、不清理 DerivedData
- 不要因为「三个同 bundle id 的安装版」再停下来——那条路本来就不需要走
