# macOS 工具栏视图树隔离

- 日期：2026-11-16
- 分支：`perf/isolate-toolbar`
- 状态：已提交、未推送、未合并。

## 变更

- 采用独立 `NSHostingView` 承载 macOS 编辑器内容；外层 SwiftUI 工具栏由只含工具栏上下文、文档标题、显示状态和语言的可比较快照驱动，不携带选中节点 ID。
- iOS 仍走原有工具栏路径；保留工具栏项、图标、顺序、间距和玻璃样式。
- 更新工具栏结构契约测试，并把按键探针窗口调整为先移到副屏，再设为 key window。

## 验证

- `swift test`：586 项，1 项跳过，0 失败。
- `xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS' -only-testing:FlorettaTests`：517 项，1 项跳过，0 失败。测试输出中 Contacts `contactsd.persistence` XPC/CoreData 错误日志；测试最终成功。
- `xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -configuration Release -destination 'platform=macOS'`：`BUILD SUCCEEDED`。
- `xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`：`BUILD SUCCEEDED`。

## 性能探针状态

| 键 | 最新已知改前 p50 | 任务书所列历史 p50 | 改后 p50 |
|---|---:|---:|---:|
| Tab | 153.4 ms | 177.5 ms | 68.2 ms |
| Return | 152.0 ms | 179.1 ms | 66.8 ms |
| 方向键 | 135.7 ms | 145.7 ms | 40.9 ms |

- 使用本工作树对应的 Release 产物直接启动：`~/Library/Developer/Xcode/DerivedData/Floretta-ghktrcrxrrzwhhamgvtuetishfug/Build/Products/Release/Floretta.app/Contents/MacOS/Floretta`；未按 bundle ID 启动安装版。
- 参数：`-FlorettaKeyLatency 30 -FlorettaKeyLatencyNodes 12`。独立运行 2 次；每次 30 轮 × 3 键，共 90 个样本（每键 n=30）；两次合计每键 n=60。每轮 `samples=90`、`abandoned=0`、`posted=90`、`landed=90`，退出码均为 0。表中改后 p50 是两轮各自 p50 的中位数；两轮值为偶数时取算术平均。

| 键 | 第 1 轮 p50 | 第 2 轮 p50 | 两轮 p50 中位数 |
|---|---:|---:|---:|
| Tab | 69.0 ms | 67.5 ms | 68.2 ms |
| Return | 65.6 ms | 67.9 ms | 66.8 ms |
| 方向键 | 42.0 ms | 39.7 ms | 40.9 ms |

- Tab 与 Return 达标（`<100 ms`）；方向键未达标（40.9 ms，目标 `<40 ms`），按原始结果记录，未调整测量方法。
- 两次报告都记录 `screens=2`，且 Cua Driver 窗口读回位置为副屏 x=2630；未截图。探针诊断同时记录 `windowIsKey=false`、`appActive=false`、`occlusionVisible=false`。因此以上数字是探针实际输出，但窗口激活/可见状态诊断为 false，作为测量有效性限制保留。

## 资源与限制

- 没有启动新的模拟器、没有截图，也没有触碰 `/Applications` 中的应用；没有清理 DerivedData。
- 两个探针进程（PID 65974、68675）均正常退出；仅卸载本任务独有的 launchd label `com.floretta.probe.20261116201102.65939`。没有终止其他进程。
- 探针脚本、plist 与原始 stdout 保留在临时目录 `/private/var/folders/p1/3pqx3j392m381v0g293m9rgc0000gn/T/opencode/floretta-probe.nSXlle`，尚未清理。
- 工作区源码、测试、任务书与本报告已随本提交纳入；构建/测试生成物未清理。
