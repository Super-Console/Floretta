# 验收记录（由 Hermes 在本机独立执行）

只记录**我自己跑出来的结果**，不采信执行者自述。

| 日期 | 批次 | 提交 | 验证方式 | 结果 |
|---|---|---|---|---|
| 2026-11-09 | P0-1 三 target 骨架 | `ef9e4f2` | `xcodebuild` macOS + iOS Simulator；读产物 Info.plist | BUILD SUCCEEDED ×2；`UIDeviceFamily=[1,2]` |
| 2026-11-09 | P0-2 模型 + 编解码 | `7a2bde9` | `xcodebuild test` | 11/11 通过（首次有 1 个真实失败，修复后全绿） |
| 2026-11-09 | P0-4 自动保存/恢复 | `59df26b` | `xcodebuild test` | 20/20 通过 |
| 2026-11-09 | P1-1 无限画布 | `4a9e6b5` | `xcodebuild test` + 启动 App 截图 | 24/24 通过；画布与工具条可见；**触控板真实手势未人工验证** |
| 2026-11-09 | P0.5 ZIP 容器 | `b8bfb2b` | `xcodebuild test` + 核对测试用例名 | 32/32 通过；容器 8 项测试覆盖 legacy 可读不覆盖、ZIP 往返与条目顺序、附件去重、缺 document.json、坏 zip、超限拒绝、inflate、CRC32 |

## 尚未验证（不能算通过）

- 画布平移/缩放/拖拽的**真实手感**（合成事件无法注入触控板手势）
- 中文 IME 组字行为（实验 A）
- 两台设备写同一文件的冲突提示（实验 B）
- iOS 真机运行（目前只到 Simulator 构建）
