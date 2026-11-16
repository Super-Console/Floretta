# 任务：把 SwiftUI 工具栏隔离出「按键就失效」的视图树

## 已测出的硬事实（不要重新调研根因，按这个改）
- 按键→首帧 p50：Tab 177.5ms / Return 179.1ms / 方向键 145.7ms（Release，12 节点）
- **把整段 `.toolbar { ... }` 从视图树里移除 → Tab 75.3ms / Return 75.7ms / 方向键 35.8ms（−102/−103/−110ms）**
- 但**只清空工具栏里的 item（11 项→0）→ 毫无收益（−0.7ms）**
- 结论：成本不在按钮数量或图标，而在「编辑器视图树上挂着一份 SwiftUI toolbar 内容」这件事本身——每次 `ViewGraph.updateOutputs` 都要跟 AppKit 工具栏桥同步一遍。
- 对照：极简 SwiftUI App 同口径 p50 仅 2–3.7ms（含用 NSViewRepresentable 包 AppKit 的情形），所以不是框架问题。

## 目标（本次只做这一件）
让编辑器每次按键**不再触发工具栏内容的重新求值/桥接同步**，同时**保留现在的外观与行为**。

允许的两条实现路线（任选，但要说明理由）：
1. **把画布搬进独立的 hosting 视图**（例如一个 `NSHostingView`/`NSHostingController` 只承载画布+检查器），工具栏留在外层稳定树里——按键只让内层树失效；
2. 或把 `.toolbar` 内容挪到一个**只在工具栏相关状态变化时才更新**的层（例如用显式的状态快照驱动，而不是让整个 body 依赖每次按键都变的选中态）。

不要做的事：
- 不要改成 NSToolbar + AppKit 手写（那是另一个方案，代价大，本次不采用）
- 不要删除任何工具栏项、不要改图标/顺序/间距/玻璃样式
- 不要改 iOS 分支的工具栏行为

## 验收（必须自己跑，贴真实输出）
1. 用仓库已有的按键探针测前后对比：Release 构建 + `-FlorettaKeyLatency 20 -FlorettaKeyLatencyNodes 12`，给出 Tab / Return / 方向键 的 p50（改前基线见上）。
2. **达标线：方向键 p50 < 40ms，Tab/Return p50 < 100ms。** 达不到就如实写数字，不许改测量方法或挑有利数据。
3. `swift test`（Core）与 `xcodebuild test -only-testing:FlorettaTests`（应用层）都必须全绿。
4. macOS 与 iOS 编译都要过（iOS 用 `-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`）。
5. 不 push、不合并到 main、不动 `/Applications`、不截图。

## 交付
- 改动说明（走了哪条路线、为什么）
- 前后 p50 对比表（三个键）
- 双端编译与两套测试的真实结果
- 未完成项与风险
