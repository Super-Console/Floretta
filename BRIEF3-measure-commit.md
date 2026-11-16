# 补做（第三轮）：跑探针 + 提交

前两轮都停在测量这一步。这轮把两个坑都堵上，照做即可，**不要停下来问**。

## 关于你上轮的顾虑（已认可，按下面做）
你说得对：`/tmp/ablate_run.py` 会卸载共享 label、`pkill -f` 太宽。**不要直接用它**，按下面写一份自己的：

- label 用本次独有：`com.floretta.probe.$$`（或带时间戳），跑完只卸载这个 label
- 杀进程只杀**你自己启动的 PID**（`$!` 记下来），**禁止任何 `pkill -f`**
- 其余照它的做法：Release 二进制直接启动 → `launchctl bootstrap gui/501 <自己的 plist>` → 窗口移副屏

## 参数与判据
- `-FlorettaKeyLatency 30 -FlorettaKeyLatencyNodes 12`
- 每组 ≥90 次采样，跑 2 次取中位数
- 基线（同口径）：Tab 177.5 / Return 179.1 / 方向键 145.7 ms
- 达标线：方向键 p50 < 40 ms，Tab/Return p50 < 100 ms

## 收尾
1. 数字填回 `logs/2026-11/toolbar-isolate.md` 的「未测」三格
2. `git add -A && git commit -m "perf(editor): isolate SwiftUI toolbar from the key-invalidated view tree"`（报告文件一起提交）
3. **不 push、不合并**
4. 数字不达标就如实写，不调测量方法

## 仍不许
不截图、不动 `/Applications`、不清理 DerivedData、不 kill 别人的进程。

如果你判断某条命令确实无法在非交互下运行，**就明确写出「哪一条、报什么错」**，不要只说「请在交互会话继续」。
