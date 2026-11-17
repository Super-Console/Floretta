# 缩小后节点与缩放性能：基线探针记录

- 日期：2026-11-16
- 当前工作树：`perf/typing-lag`，HEAD `4e2c1bd56fcd0380d59afeab65355ef74932741`，使用预先构建于 23:11 的 Release 二进制。
- 对照：独立干净 detached worktree `/Users/TimmySheep/AWS/floretta/.worktrees/typing-lag-baseline`，HEAD 与 `main` 均为 `4e2c1bd56fcd0380d59afeab65355ef74932741`。
- 本记录只包含基线/当前探针结果；它**不是 BRIEF2 的功能完成报告**。没有修改或提交产品代码，也没有动原有未提交的第一批文件。

## Release 基线构建

在上述基线 worktree 根目录运行：

```sh
xcodebuild build -scheme Floretta-macOS -configuration Release -derivedDataPath /tmp/dd-base CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

结果：`** BUILD SUCCEEDED **`。构建未访问钥匙串，也没有签名错误。基线可执行文件为 `/tmp/dd-base/Build/Products/Release/Floretta.app/Contents/MacOS/Floretta`；当前可执行文件为用户提供的 `/tmp/dd-typing/Build/Products/Release/Floretta.app/Contents/MacOS/Floretta`。

## Tab / Enter / 方向键门槛

两边均直接启动 Release 二进制，参数相同：`-FlorettaKeyLatency 30 -FlorettaKeyLatencyNodes 12`。每次 30 轮、每键 30 个样本；两次均为 `samples=90`、`posted=90`、`landed=90`、`abandoned=0`、退出码 0。

| 构建 | Tab p50 / p95 | Enter p50 / p95 | 方向键 p50 / p95 |
|---|---:|---:|---:|
| 基线 `4e2c1bd` | 237.2 / 1050.5 ms | 266.6 / 903.8 ms | 78.6 / 353.9 ms |
| 当前 Release | 95.7 / 257.0 ms | 95.0 / 127.8 ms | 54.2 / 70.4 ms |

门槛 `<100 ms / <100 ms / <50 ms`：当前 Tab、Enter 通过；方向键 **54.2 ms，未通过**。这是每构建单次探针，不应外推为重复运行的中位数。

窗口由探针移至副屏；Cua Driver 回读 `x=2620, y=-355, 960×680`，`is_on_screen=true`，两屏均被探针识别。驱动诊断为 `appActive=true`、`occlusionVisible=true`、`windowIsKey=false`（结束时 `windowIsKeyAfter=true`）。因此样本成功落入探针，但窗口在采样起点不是 key window，此限制一并保留。

## 画布性能探针

使用同一 `-FlorettaUITest` 隔离用户文档/默认值，分别运行 `-FlorettaPerfNodes 12` 与 `-FlorettaPerfNodes 500`，语言参数两边相同。内置探针每次运行固定约 3 秒 pan、6 秒缩放（0.5↔2.0 两轮）、3 秒拖动；结果均退出码 0。缩放窗口在四次有效运行中都回读为副屏 `x=2620`。

下表只列内置探针实际输出的缩放阶段。`p95 draw` 是绘制函数耗时分位数，不是帧间隔分位数；`最长帧间隔` 是探针记录的最长 display-link 间隔。

| 节点数 | 构建 | 平均 FPS | 最低 0.5 秒桶 FPS | p95 draw | max draw | 最长帧间隔 | body 求值 | 最大可见节点 |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 12 | 基线 | 95.7 | 60 | 5.1 ms | 9.5 ms | 207.8 ms | 10 | 12 |
| 12 | 当前 | 69.8 | 2 | 5.2 ms | 225.1 ms | 567.9 ms | 10 | 12 |
| 500 | 基线 | 69.5 | 4 | 9.8 ms | 14.5 ms | 516.6 ms | 10 | 55 |
| 500 | 当前 | 67.7 | 4 | 9.3 ms | 14.3 ms | 504.4 ms | 10 | 55 |

探针报告 `displayMaxFPS=120`。500 节点单次结果的均值和 p95 draw 接近；12 节点两次结果的 tick/FPS 与最长间隔差异很大。每个组合只跑了一次，且该探针没有禁用 App Nap 的活动声明，故这些数据只能作为本次原始观测，**不足以证明当前构建改善或退化**。首个基线 500 节点运行时窗口仍是零尺寸/不可见，该次结果已作废；表中基线 500 是在副屏回读确认后的重跑。

## 尚未取得的 BRIEF2 数据与限制

- 当前内置画布探针只输出每阶段 `p95DrawMs`、均值、最大 draw、帧率和最长 display-link 间隔；**不输出帧间隔 p50/p95，也不记录每步布局重算次数**。`bodyEvaluations=10` 只是 SwiftUI body 求值次数，不能替代布局计数。
- 它只驱动 50%–200% 的固定缩放；`CanvasViewport.minimumScale` 是 0.5，正常缩放入口会 clamp 到 0.5。因此这组 Release 探针无法通过同一路径测到 0.25 / 0.1，也没有逐节点输出可见集合、裁剪矩形和最终字号。没有据此编造 A 的 12×4 逐节点表或根因结论。
- 当前源码中存在 `CanvasDetail` 与 `CanvasTextLOD`，因此任务书中“全仓没有 LOD 机制”并不适用于此 checkout；存在这些符号本身不证明低缩放可见性正确。
- 现有自动入口没有 inspector 展开/收起或连续窗口边缘拖动的驱动/计数，因此 E/F 的帧 p50/p95、布局/绘制归因和 resize 重算次数仍未测；本次没有执行 GUI 手动操作，也没有截图。
- 每次 AppKit 进程的 stderr 都出现以下其中一条原文；对应进程仍写出了结果并以退出码 0 结束。原因尚未确认，故作为限制记录：
  - `sandbox_extension_issue_file_to_process failed for /tmp/dd-base/Build/Products/Release/Floretta.app: 1 (Operation not permitted)`
  - `sandbox_extension_issue_file_to_process failed for /tmp/dd-typing/Build/Products/Release/Floretta.app: 1 (Operation not permitted)`
- 例如实际启动命令为 `launchctl bootstrap gui/501 /tmp/floretta-zoom-runners.MOZCmT/com.floretta.zoom.base-key.42685.plist`；画布探针 plist 的 `ProgramArguments` 为对应的 Release 可执行文件、`-FlorettaUITest`、`-FlorettaPerfNodes 12|500`、`-FlorettaLanguage zh-Hans`、`-AppleLanguages (zh-Hans)`、`-AppleLocale zh_CN`。E/F 没有可运行的内置驱动命令，因此没有伪造命令错误；确切限制是现有二进制不提供 inspector 动画或窗口缩放事件的启动参数/计数输出。

## 进程与资源

所有进程均通过本任务独有的 `launchctl bootstrap gui/501 <plist>` label 启动；均自然退出，退出码 0。没有发送 kill 信号、没有使用 `pkill -f`，也没有终止其他进程。

| 运行 | label | PID | 结果 |
|---|---|---:|---|
| 基线按键 | `com.floretta.zoom.base-key.42685` | 42701 | 90 样本 |
| 当前按键 | `com.floretta.zoom.current-key.46341` | 46345 | 90 样本 |
| 基线 500 节点首跑（作废） | `com.floretta.zoom.base-canvas.45326` | 45329 | 窗口不可见 |
| 当前 500 节点 | `com.floretta.zoom.current-canvas.48257` | 48260 | 副屏回读通过 |
| 基线 500 节点重跑 | `com.floretta.zoom.base-canvas2.49261` | 49264 | 副屏回读通过 |
| 基线 12 节点 | `com.floretta.zoom.base-12.53005` | 53009 | 副屏回读通过 |
| 当前 12 节点 | `com.floretta.zoom.current-12.54032` | 54035 | 副屏回读通过 |

收尾核对时没有存活的本任务 Floretta 或 `xcodebuild` 进程；launchd 记录各 label 为 `job state = exited`。`/tmp/dd-base` 与用户提供的 `/tmp/dd-typing` 均保留，未清理 DerivedData。基线 worktree 和 `/tmp/floretta-zoom-runners.MOZCmT`（plist/stdout/stderr）也暂时保留，待用户确认后再清理。
