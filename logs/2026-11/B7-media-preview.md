# B7 节点内音视频预览

- 变更：音频附件在画布视口内异步抽取 PCM 并绘制波形；音频/视频节点异步读取时长并显示 `mm:ss` 角标；缩略图与波形复用 `ThumbnailFileCache`。
- 安全与性能：媒体载荷由 `FilePreviewSpill` 流式写入临时文件；解码在后台执行；波形采样限制为 512 点；缺失/不可读/解码失败回退为空预览。
- 验证：Core 测试 347 项通过；macOS 与 iOS `xcodebuild build` 均通过，日志 `error:` 计数均为 0；Core import 检查通过。
- 资源：本任务未启动 Simulator.app；检查时已有 iOS Simulator booted，且被另一既存 `xcodebuild test` 使用，故未执行 `shutdown all`，避免中断其他任务。两个构建输出目录为 `/tmp/b7-mac`、`/tmp/b7-ios`，尚未清理。
