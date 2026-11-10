# 验收记录（由 Hermes 在本机独立执行）

只记录**我自己跑出来的结果**，不采信执行者自述。

| 日期 | 批次 | 提交 | 验证方式 | 结果 |
|---|---|---|---|---|
| 2026-11-09 | P0-1 三 target 骨架 | `ef9e4f2` | `xcodebuild` macOS + iOS Simulator；读产物 Info.plist | BUILD SUCCEEDED ×2；`UIDeviceFamily=[1,2]` |
| 2026-11-09 | P0-2 模型 + 编解码 | `7a2bde9` | `xcodebuild test` | 11/11 通过（首次有 1 个真实失败，修复后全绿） |
| 2026-11-09 | P0-4 自动保存/恢复 | `59df26b` | `xcodebuild test` | 20/20 通过 |
| 2026-11-09 | P1-1 无限画布 | `4a9e6b5` | `xcodebuild test` + 启动 App 截图 | 24/24 通过；画布与工具条可见；**触控板真实手势未人工验证** |
| 2026-11-09 | P0.5 ZIP 容器 | `b8bfb2b` | `xcodebuild test` + 核对测试用例名 | 32/32 通过；容器 8 项测试覆盖 legacy 可读不覆盖、ZIP 往返与条目顺序、附件去重、缺 document.json、坏 zip、超限拒绝、inflate、CRC32 |

## 打包门禁（iOS 上传前）

Archive 并 export 之后、任何上传之前，检查的是 **iOS App 包里的** `Info.plist`。产物名是 `Floretta-iOS.app`。仓库里的 `Floretta/iOS/Info.plist` 不能代替这一步。

- Archive：`<archive>.xcarchive/Products/Applications/Floretta-iOS.app/Info.plist`
- IPA：解开后的 `Payload/Floretta-iOS.app/Info.plist`

包内 Info.plist 默认是二进制，布尔值不是文本，直接 `grep` 看不到 `true` / `YES`。先转成 XML，再确认 `LSSupportsOpeningDocumentsInPlace` 的值是 `<true/>` 或 `YES`。键缺失、值不是 true/YES、或命令退出码不是 0，都禁止上传。

```bash
plutil -convert xml1 -o - "$IOS_APP/Info.plist" \
  | grep -A1 '<key>LSSupportsOpeningDocumentsInPlace</key>' \
  | grep -Eq '<true[[:space:]]*/>|>YES<'
```

`$IOS_APP` 指向上面两个路径之一的 `Floretta-iOS.app`。通过之后才能交给 Transporter、`altool` 或 App Store Connect。本项不要求、也不添加 `UISupportsDocumentBrowser`。

## 尚未验证（不能算通过）

- 画布平移/缩放/拖拽的**真实手感**（合成事件无法注入触控板手势）
- 中文 IME 组字行为（实验 A）
- 两台设备写同一文件的冲突提示（实验 B）
- iOS 真机运行（目前只到 Simulator 构建）
