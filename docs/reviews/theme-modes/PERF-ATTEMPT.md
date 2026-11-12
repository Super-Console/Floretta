# 本轮画布性能协议测量记录（PR #119）

时间均为 Asia/Shanghai（CST）。方法与 `docs/reviews/CANVAS-PERF-BASELINE.md` 相同，夹具为 `docs/reviews/perf-fixtures/canvas-perf-{50,200,500}.floretta`，启动参数 `-FlorettaUITest -FlorettaPerfNodes <N>`。没有编造 FPS 或内存数字。

## 构建（成功）

```
xcodebuild -project Floretta.xcodeproj -scheme Floretta-macOS \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=JY5U4D6JD3 \
  -derivedDataPath /tmp/theme-modes-perf-dd build
```

- 日志：`/tmp/theme-modes-perf-build.log`
- START 2026-11-12 21:57:49 CST，END 21:59:01 CST，EXIT 0
- 产物：`/tmp/theme-modes-perf-dd/Build/Products/Release/Floretta-macOS.app`
- 身份：Apple Development: timmysh34@icloud.com (L6544N692J)，Team JY5U4D6JD3
- entitlements：`com.apple.security.app-sandbox`、`com.apple.security.files.user-selected.read-write`、`com.apple.security.get-task-allow`

未改工程签名，只在命令行覆盖。

## 启动与失败

1. 直接执行产物内二进制（2026-11-12 22:01:18 CST 起，`/tmp/theme-modes-perf/batch.log`、`mac-TMa-50.out`）：出现 `sandbox_extension_issue_file_to_process failed for /tmp/theme-modes-perf-dd/Build/Products/Release/Floretta-macOS.app: 1 (Operation not permitted)`，90 秒后 timeout，退出 124（22:02:48 CST）。无 `FLORETTA_PERF_RESULT`。
2. 拷贝到 `/tmp/theme-modes-perf/Floretta-macOS.app` 后再 `--force --deep` 重签，一度丢掉 entitlements。改回从 DerivedData 原样拷贝（entitlements 完整）后：
   - `/usr/bin/timeout 40 …/Floretta-macOS -FlorettaUITest -FlorettaPerfNodes 50`（`/tmp/theme-modes-perf/trial-50.out`，22:03:48–22:04:28 CST）仍是同一 sandbox 提示，退出 124。
   - `open -n -W` 经 Terminal.app `do script`（`/tmp/theme-modes-perf/open-50.out`，22:15:50 CST）：进程存在，System Events 为 `frontmost=true, visible=true, windows=0`。
3. 用今早已跑通协议的 `/tmp/canvasperf/mac-D2.app` 在同一会话里 `launchctl asuser 501 open`，同样是 0 窗口，容器 JSON 未更新。

容器路径 `~/Library/Containers/net.timhuang.floretta/Data/tmp/canvas-perf-50.json` 的 mtime 始终是 2026-11-12 18:28:18 CST（上一次画布性能确认轮留下的旧结果）。本轮没有覆盖它，也没有把它当作本 tip 的新测量。

因此内存、帧率两行没有数字可写。

## 改用 XCUITest 路径后的实测（500 节点）

Hubert 要求停止失败的 macOS 直接启动路径，改走已经能创建窗口的 XCUITest。本轮在 iPad 模拟器 `ASC-iPadPro13-M5` 上用 Release + `-FlorettaUITest -FlorettaPerfNodes 500` 跑未修改的 PR #117 `CanvasPerfProbe`。测试 `testCanvasPerf500ViaUITest` 只负责启动并等到进程退出，不改写探针。

- 日志：`/tmp/theme-modes-perf500-ios.log`
- START 2026-11-12 23:03:10 CST，END 23:04:54 CST，EXIT 0，`** TEST SUCCEEDED **`
- 探针 JSON：模拟器容器 `…/tmp/canvas-perf-500.json`（mtime 2026-11-12 23:04:53 CST），已复制为 `docs/reviews/theme-modes/canvas-perf-500-ipad-xcuitest.json`
- `finishedAt`：2026-11-12T15:04:53Z（23:04:53 CST）
- 峰值内存：64.6 MB
- 平均 / 最低 FPS：平移 1.0 / 0，缩放 0.8 / 0，拖动 0.9 / 0
- 不得把同容器里 18:30 CST 的 `canvas-perf-50.json` / `canvas-perf-200.json` 当作本 tip 的测量。

## 对照实验（同一启动器，2026-11-12 23:15–23:22 CST）

Hubert 指出 1.0 / 0.8 / 0.9 FPS 比同机基线低约一个数量级，不得用「可能偏慢」带过。对照只用同一套 `testCanvasPerf500ViaUITest`、同一 PR #117 探针、同一 500 节点夹具。

1. 对照 `8e50c1212d9f784ec6b38ba434f8c77cb9206cf6`（`origin/main` / merge-base，无 theme-modes）：`/tmp/theme-modes-baseline-perf500.log`，23:15:21–23:16:58 CST，EXIT 0。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12.json`，`finishedAt` 2026-11-12T15:16:56Z。峰值 97.4 MB；平移 59.7 / 58，缩放 57.3 / 50，拖动 59.7 / 58。同一启动器在对照上不是 1 FPS，所以 1 FPS 不是启动器开销。
2. `fae6453` 复核（同一启动器）：`/tmp/theme-modes-perf500-tip-confirm.log`，23:18:43–23:19:29 CST，EXIT 0。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-fae6453-before-fix.json`，`finishedAt` 2026-11-12T15:19:27Z。峰值 89.2 MB；平移 1.0 / 0，缩放 0.8 / 0，拖动 0.9 / 0。确认是本分支回归。原因是 `canvasText` 每帧为每个可见节点构建带级联的 CTFont（以及 Canvas `.id`）。
3. 去掉那条热路径后再测：`/tmp/theme-modes-perf500-fix.log`，23:21:11–23:22:09 CST，EXIT 0。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-xcuitest.json`，`finishedAt` 2026-11-12T15:22:08Z。峰值 73.4 MB；平移 59.3 / 56，缩放 55.7 / 38，拖动 59.7 / 58。与对照同量级。模式切换仍用 `Font.system(design:)` 区分，未重拍已通过的截图。

## 缓存 CTFont 后再测（2026-11-12 23:33–23:34 CST）

Hubert 否决了把画布退回 `Font.system(design:)` 的修法：那样选 EB Garamond / Inter 仍会画成系统衬线或无衬线。正确修法是按 (family, design, size) 缓存已解析的 CTFont，每帧只查找。

同一套 `testCanvasPerf500ViaUITest`、同一 PR #117 探针、同一 500 节点夹具，Release：`/tmp/theme-modes-perf500-cache.log`，23:33:49–23:34:49 CST，EXIT 0，`FLORETTA_PERF_UITEST_DONE elapsed=24.2`。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-xcuitest.json`，`finishedAt` 2026-11-12T15:34:47Z。峰值 105.5 MB；平移 59.3 / 56，缩放 53.7 / 40，拖动 59.7 / 58。平移和拖动落在对照 57–60 区间；缩放平均 53.7，略低于对照 57.3。中文级联在缓存填满后仍由 macOS `ThemeFontCascadeTests` 8/0 断言为宋体（23:30:23–23:31:07 CST，`/tmp/theme-modes-font-mac-test3.log`）。

## 干净树重测与去掉每查找一把锁（2026-11-13 00:20–00:25 CST）

临时 UITest 驱动放在 gitignored 的 `.scratch/perf-driver`（对照则用 `git archive` 的 `/tmp/theme-modes-8e50c12-remeasure`），不改工作树、不进 tip。同一套 `testCanvasPerf500ViaUITest`、同一 PR #117 探针、同一 500 节点夹具、同一模拟器、Release。

1. 本 tip 产品代码 `e379209963e8ee5ccfa6314ede7d52c303b3e42c`（每帧快照 + 绘制只读引用）：`/tmp/theme-modes-perf500-e379209.log`，START 00:20:11，END 00:21:51 CST，EXIT 0，`FLORETTA_PERF_UITEST_DONE elapsed=24.6`。日志里 `HEAD=e379209…`，测量前后 `git status --porcelain` 均为空。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-e379209.json`，`finishedAt` 2026-11-12T16:21:50Z（00:21:50 CST），sha256 `c19dbd0f2915ffa02c8c180b679845ebcda7b99d342dd224c3b7b2c5537cd24f`。峰值 94.3 MB；平移 59.0 / 56（178）；缩放 54.2 / 42（326）；拖动 59.7 / 58（179）。缩放平均仍低于门禁 ≥55。
2. 同参数重测对照 `8e50c12`：`/tmp/theme-modes-baseline-perf500-remeasure.log`，START 00:23:54，END 00:25:33 CST，EXIT 0，`elapsed=25.2`。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12-remeasure.json`，`finishedAt` 2026-11-12T16:25:32Z（00:25:32 CST），sha256 `5c32075086f88ed951af1bdb670ec06f22ca5454393c97176756e11905749724`。峰值 105.2 MB；平移 59.3 / 56（179）；缩放 55.5 / 40（334）；拖动 59.7 / 58（180）。与 11-12 晚间对照（97.4 MB；59.7 / 57.3 / 59.7）一并据实列出，不把当时的 54.2 写成 57–60。同批对照从 57.3 落到 55.5，探针噪声约 ±2；`e379209` 的 54.2 相对 55.5 差 1.3，落在噪声带内，不应写成回归。

## 0.5pt 量化键与 LRU 后再测（2026-11-13 00:41–00:43 CST）

Hubert 指出缩放时字号连续变化，1/64 pt 的缓存键几乎每帧未命中。本轮把字号按最近的 0.5 pt 写入键，并给已按尺寸拷贝的表加上 256 条容量上限与 LRU。每帧快照、绘制只读引用、以及把真实家族写进 `NSAttributedString` 的路径保持不变，不退回 `Font.system(design:)`。

同一套 `testCanvasPerf500ViaUITest`、同一 PR #117 探针、同一 500 节点夹具、同一模拟器、Release，干净树产品提交 `9a92549e0d68f26ab9e8fcca079df64de9b1aa6e`：`/tmp/theme-modes-perf500-9a92549.log`，START 00:41:52，END 00:43:53 CST，EXIT 0，`FLORETTA_PERF_UITEST_DONE elapsed=25.5`。日志打印 `HEAD=9a92549e0d68f26ab9e8fcca079df64de9b1aa6e`，测量前后 `git status --porcelain` 均为空。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-9a92549.json`，`finishedAt` 2026-11-12T16:43:51Z（00:43:51 CST），sha256 `1de8960e82a6ec35373d41c034a05546e65ab93e9b17d95a9fa4b008095d50b0`。峰值 92.8 MB（相对 `e379209` 的 94.3 MB 为 −1.5 MB，相对重测对照 105.2 MB 为 −12.4 MB，增量低于 20 MB）；平移 59.7 / 58（179）；缩放 55.3 / 44（333）；拖动 59.7 / 58（179）。缩放平均 55.3 达到数字门禁 ≥55；与同批对照 55.5 差 0.2，探针噪声约 ±2，无跨量级差异。不得写成 57–60，也不在这里宣布通过。
