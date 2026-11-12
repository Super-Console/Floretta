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
