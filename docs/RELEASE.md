# 发布与版本号纪律

## 版本号规则

- 每次上传 TestFlight 前，`CURRENT_PROJECT_VERSION` 必须比上次已上传构建号 **+1**，且不得重用已上传 build number。
- `MARKETING_VERSION` 当前保持 `1.0`；只有产品版本策略明确调整时才改，不因每次 TestFlight 上传而递增。
- 当前 `Floretta.xcodeproj/project.pbxproj` 的项目配置为 `CURRENT_PROJECT_VERSION = 10`、`MARKETING_VERSION = 1.0`（本次检查）。上传后应在 App Store Connect 回读 build 号与处理状态，不能只凭本地归档推断上传成功。
- 设置页 /「关于」应显示版本号和构建号。当前两处都读取 `AppInfo.version`；它在 `CFBundleShortVersionString` 与 `CFBundleVersion` 都存在时显示 `版本 (构建号)`。本次源码检查确认显示路径存在；打包验收仍须在实际安装包中确认两个 bundle 值均正确。本任务不改代码。

## 打包前检查清单

1. [ ] 确认目标分支与提交；工作区无意外改动，提交内容只包含本次发布所需文件。
2. [ ] 检查 `MARKETING_VERSION` 保持 `1.0`，`CURRENT_PROJECT_VERSION` 比 App Store Connect 最近一次已上传 build 大 1。
3. [ ] 检查文档打开位置配置：
   ```sh
   grep -n 'LSSupportsOpeningDocumentsInPlace' Floretta/macOS/Info.plist Floretta/iOS/Info.plist
   ```
   确认 plist 中存在且值符合预期。
4. [ ] 检查所有项目配置的版本值：
   ```sh
   grep -n 'CURRENT_PROJECT_VERSION' Floretta.xcodeproj/project.pbxproj
   grep -n 'MARKETING_VERSION' Floretta.xcodeproj/project.pbxproj
   ```
   确认相关 target/configuration 不存在旧值或不一致值。
5. [ ] 结构检查：
   ```sh
   plutil -lint Floretta/macOS/Info.plist
   plutil -lint Floretta/iOS/Info.plist
   plutil -lint Floretta.xcodeproj/project.pbxproj
   ```
6. [ ] 上传前确认两个主 Info.plist 均声明非豁免加密状态为 `false`：
   ```sh
   plutil -lint Floretta/iOS/Info.plist Floretta/macOS/Info.plist
   for f in Floretta/iOS/Info.plist Floretta/macOS/Info.plist; do
     echo "$f: $(plutil -extract ITSAppUsesNonExemptEncryption raw "$f")"
   done
   ```
   两个文件都必须输出 `false`。
7. [ ] 运行受影响测试、Core import 检查和双端结构/编译验证；SSH 无法签名的限制见 `AGENTS.md`，签名归档在 Mac 图形会话完成。
8. [ ] 归档后核对 archive 的 marketing/build 版本，再上传 TestFlight。
9. [ ] 上传后回读 App Store Connect 构建号及状态，记录结果；失败或处理中不可记为已完成发布。
