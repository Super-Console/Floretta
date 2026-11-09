# 状态

## 当前阶段

P0-1 工程骨架已落盘，等待总指挥在本机 Mac 上 `xcodebuild` 验收。P0-2 及之后未开始。P4（TestFlight）未做。

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

## 下一步

本机 Mac 拉取后分别构建 scheme `Floretta-macOS` 与 `Floretta-iOS`（iPhone 模拟器、iPad 模拟器）。构建错误贴回再改。通过后再放行 P0-2（`MindMapDocument`）。

## P0-1 申报

任务书里的三端落成两个 Xcode application target。没有第三个 `PBXNativeTarget`，也没有测试 target 或 framework。iPad 走 Universal 的 `Floretta-iOS`。

| Target | Scheme | 平台 | 产物 |
|---|---|---|---|
| `Floretta-macOS` | `Floretta-macOS` | macOS | `Floretta-macOS.app` |
| `Floretta-iOS` | `Floretta-iOS` | iOS Universal（iPhone + iPad） | `Floretta-iOS.app` |

iPad 为原生 Universal，依据：

- `Floretta/iOS/Info.plist` 中 `UIDeviceFamily` 为整数数组 `[1, 2]`
- iOS Debug / Release 均设置 `TARGETED_DEVICE_FAMILY = 1,2`
- `UIRequiresFullScreen = false`
- 独立的 `UISupportedInterfaceOrientations~ipad`（上下左右）
- 含空的 `UILaunchScreen`
- `SUPPORTS_MACCATALYST = NO`，`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`。Mac 只走 `Floretta-macOS`

工程与源码：

- `Floretta.xcodeproj` 为手写 classic 格式：`objectVersion = 63`，`compatibilityVersion = Xcode 15.0`，`LastUpgradeCheck = 1600`。Xcode 27.2 打开后可能提示升级到推荐设置。
- 共享源码，两个 target 都编译：`Floretta/Shared/FlorettaApp.swift`、`Floretta/Shared/ContentView.swift`
- 空白窗口只用 SwiftUI `WindowGroup` 与 `Color.clear`。没有自绘控件，没有 `Canvas`，没有需要报批的自定义控件（§1.1）
- 本批是空窗口，没有可复用的编辑实现，因此没有拷贝 Mindscape / Brainstorm / SwiftFlow 的代码，也没有加第三方依赖（§1.2）
- `SWIFT_VERSION = 6.0`，`SWIFT_STRICT_CONCURRENCY = complete`
- `MACOSX_DEPLOYMENT_TARGET = 26.0`，`IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- 仓库名与目录名仍是 `Supernode`
- `CFBundleDisplayName` / `CFBundleName` 为 Floretta。target 名与 `.app` 名保持 `Floretta-macOS` / `Floretta-iOS`
- macOS：App Sandbox + Hardened Runtime，签名身份 `-`（Sign to Run Locally）。entitlements 含 user-selected read-write，只是模板能力，没有文件选择界面
- iOS 模拟器：`CODE_SIGNING_ALLOWED[sdk=iphonesimulator*] = NO`，`CODE_SIGNING_REQUIRED[sdk=iphonesimulator*] = NO`。工程里没有写 `DEVELOPMENT_TEAM`
- App Icon 与 AccentColor 是空槽，留给 P3。图标参考图未改
- macOS Info.plist 由 `GENERATE_INFOPLIST_FILE = YES` 在构建时生成
- Bundle ID 暂用 `app.floretta.macos` 与 `app.floretta.ios`。仓库里没有既定反向域名

P4 只记录、不实现：TestFlight 内部测试以后再做，邀请 `timmysh34@icloud.com`，Team `JY5U4D6JD3`。本批不上传、不配置证书、不把 ASC 凭据写进工程。

### 已验证

1. `command -v xcodebuild`、`swift`、`swiftc`、`plutil`：都不在 PATH 里。没有伪造构建日志。
2. Python 解析 `project.pbxproj`：38 个对象 ID，全部是 24 位十六进制，引用闭合。2 个 `PBXNativeTarget`，`productType` 均为 `com.apple.product-type.application`。两个 target 的 Compile Sources 都是 `FlorettaApp.swift` 与 `ContentView.swift`，Resources 各一份 `Assets.xcassets`。无 package 引用，无 shell script phase。文件引用在磁盘上均存在。
3. `plistlib` 读取 `Floretta/iOS/Info.plist`：`UIDeviceFamily == [1, 2]`，`UIRequiresFullScreen == false`，iPad 四方向齐全。`Floretta-macOS.entitlements` 可解析。
4. 标准库 `json` 解析两边 asset catalog 的 `Contents.json`，通过。
5. XML 解析 `contents.xcworkspacedata` 与两个 shared scheme，通过。`Floretta-macOS.xcscheme` 的 Blueprint 指向 `E10000000000000000000001`，`Floretta-iOS.xcscheme` 指向 `E10000000000000000000002`。

### 未验证

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

- `xcodebuild` 的 macOS Debug/Release、iOS Simulator（iPhone）、iOS Simulator（iPad）、真机，全部没跑
- Mac、iPhone、iPad 上的空白窗口都没看到
- 部署目标 26.0 能否被 Xcode 27.2 与对应 SDK 接受
- 签名。没有 Development Team。Mac ad-hoc + 沙盒能否直接 Run，未测。iOS 模拟器免签名设置未测。真机安装未配置
- 空 App Icon 会不会让 actool 把构建打成 error，未测
- Swift 6 共享源码能否编译。本机没有 `swiftc`，也没有 SwiftUI SDK

## 记录

| 日期 | 批次 | 结果 | 备注 |
|---|---|---|---|
| 2026-11-09 | 仓库初始化 | 完成 | 骨架、任务书、格式矩阵、参考清单落盘 |
| 2026-11-09 | 环境就绪 | 完成 | Pro 工作副本 + push 凭据实测可推 |
| 2026-11-09 | 任务书合并 | 完成 | 主线任务 + App 图标任务合并进 TASKBOOK-001；产品名定为 Floretta；图标参考图入库 |
| 2026-11-09 | 约束追加 | 完成 | 新增 D-8 原生控件 / D-9 复用开源 / D-10 TestFlight 交付；已写入 TASKBOOK 1.1、1.2、5.1 |
| 2026-11-09 | P0-1 | 已提交，云端未构建 | 两 target 覆盖 Mac / iPhone / iPad。云端不能跑 Xcode；本机 Mac 拉取后 xcodebuild，构建错误贴回再改。合并前 `origin/main` 不含本批 |
