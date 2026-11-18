# 性能实测记录 — 2026-11-15

机器：Mac14,10（Apple silicon）；macOS 27.2；Xcode 27.2。测试目标为 macOS；没有启动模拟器，也没有运行 `xctrace record`。

## 500 节点单帧 CPU 布局耗时

读取 `docs/reviews/perf-fixtures/canvas-perf-500.floretta`，通过 `ZipContainer` 解码 500 节点 fixture。每轮执行一次 `LayoutEngine().layout(document)` 和画布命中查询，20 次取 `ContinuousClock` 平均值。

结果：10.5815396 ms/轮；倒数换算约 94.5042 FPS。**这是单帧 CPU 布局耗时换算值，不是屏幕实测 FPS**；未计入绘制、合成、屏幕刷新等成本。按该 CPU 耗时与 18.18 ms/帧预算比较，达标。

## 1000 节点文档打开（解码 + 布局准备）

从同一 500 节点 fixture 复制根节点和自由节点，为副本递归生成新 UUID，编码为 1000 节点文档。每轮计时仅覆盖 `FlorettaCodec.decode(encoded)` 和 `LayoutEngine().layout(decoded)`，5 次取平均；fixture 读取、文档合成及编码在计时区间之外。该 Core 层指标**不含 UI 首帧**。

结果：21.6021666 ms 平均；解码后确认文档为 1000 节点，布局输出 1000 frames。相较 `<1.5s` 门槛达标。

## 冷启动到首帧

**未测：需要 GUI 会话与 Instruments，命令行环境不可得。** 本次未启动应用、模拟器或 Instruments 采样，未推测数值。

## 命令与原始输出

两项测试分别单独运行，使用命令（将 `<TestName>` 替换为以下两个测试名）：

```sh
xcodebuild test -scheme Floretta-macOS -destination 'platform=macOS' \
  -only-testing:FlorettaTests/CanvasTests/<TestName> \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-perf
```

Xcode 测试输出原文摘录：

```text
Test Case '-[FlorettaTests.CanvasTests testPerfMeasure500NodeSingleLayoutAndHitTest]' started.
PERF_500_SINGLE_LAYOUT_HITTEST iterations=20 nodes=500 average_seconds=0.0105815396 converted_cpu_fps=94.50420617430757
Test Case '-[FlorettaTests.CanvasTests testPerfMeasure500NodeSingleLayoutAndHitTest]' passed (0.368 seconds).
** TEST SUCCEEDED **
```

```text
Test Case '-[FlorettaTests.CanvasTests testPerfMeasure1000NodeDecodeAndLayoutPreparation]' started.
PERF_1000_DECODE_LAYOUT_PREP iterations=5 document_nodes=1000 layout_frames=1000 average_seconds=0.0216021666
Test Case '-[FlorettaTests.CanvasTests testPerfMeasure1000NodeDecodeAndLayoutPreparation]' passed (0.259 seconds).
** TEST SUCCEEDED **
```
```
