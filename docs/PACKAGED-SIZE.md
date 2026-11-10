# 打包体积门禁

状态：生效
建立：2026-11-10

E4。打进包里的 App 要同时满足：

| 平台 | 预算 | 比较 |
|---|---|---|
| iOS | 15 MB | 测得字节 **小于** 15 × 1024² |
| macOS | 25 MB | 测得字节 **小于** 25 × 1024² |

MB 与 `docs/STREAMING.md` 一样，按 1024² 计。脚本是 `scripts/check-packaged-app-size.sh`。超过预算进程退出码为 1。

GitHub Actions 只有 `ubuntu-24.04`（`FlorettaCore` workflow），没有 macOS runner，也没有 Xcode，打不出 Release `.app` / `.ipa`。这一项不改签名、描述文件、钥匙串，也不归档、不上传。

## CI 量的是什么

`packaged-size` job 不传路径，走下面这份可重复的和，并用上面两个预算卡它。

1. `swift build -c release` 编出的每个 `FlorettaCore` / `FlorettaUI` 的 `.swift.o`。自动库没有客户端时 SPM 不产出 `libFlorettaCore.so`，所以脚本把这些 `.o` 和一份空的 `main` 链成可执行文件，再 `strip --strip-unneeded`（DWARF 留在 dSYM，不进 App），减去同样方式编出的空可执行文件。`libswift*.so` 仍是动态库，不计入：iOS 26 / macOS 26 的 Swift 运行时在系统里。
2. 每个链接了该库的 App 与 appex 各算一份。`Package.swift` 没有把库标成 dynamic，Xcode 按静态方式把同一份代码链进每个可执行文件。当前工程是 iOS 上 FlorettaCore ×2（App + 分享扩展）、FlorettaUI ×1；macOS 上 FlorettaCore ×4（App + 分享扩展 + 两个 Quick Look）、FlorettaUI ×1。
3. 这些 target 的 Copy Bundle Resources 在磁盘上的字节（asset catalog 的源文件，不是 `actool` 编出来的 `Assets.car`），加上该 target Release 配置的 `INFOPLIST_FILE`。嵌入的 appex 算进宿主 App。

不在这个和里：

- `Floretta/` 里 SwiftUI 编出来的 Mach-O（`app_swift_source_bytes` 只打印源文件字节，不加入预算）
- SwiftFlow 0.3.1
- 代码签名
- `DerivedData` 的 Intermediates / Index、`dSYM`

所以 CI 的数是「能在 Linux 上编出来的发布库，按链接次数相加，再加上会拷进包的资源源文件」。它和 15 MB / 25 MB 用同一个小于比较。资源源文件通常大于编出来的 `Assets.car`。SwiftUI 与 SwiftFlow 的机器码不在数里，因此低于预算不能代替已签名 `.app` 的测量。

## 有包的时候量什么

在有 Xcode 产物的机器上：

```bash
scripts/check-packaged-app-size.sh \
  --ios path/to/Floretta-iOS.app \
  --macos path/to/Floretta-macOS.app
```

也接受 `.ipa` 和 `.xcarchive`。

| 输入 | 计入预算的字节 |
|---|---|
| `.app` | 包内普通文件的表观大小 |
| `.ipa` | `Payload/*.app` 里的普通文件。zip 本身、`SwiftSupport`、`Symbols` 不算 |
| `.xcarchive` | `Products/Applications/*.app` 里的普通文件。旁边的 `dSYM` 不算 |

`Intermediates.noindex`、`Index.noindex`、`ModuleCache.noindex`、以及以 `.dSYM` 结尾的路径直接拒绝。脚本不调用 `xcodebuild`。

## 运行时

`Floretta/`、`FlorettaCore/`、`FlorettaUI/` 里出现 Node 或 Python 解释器、`node_modules`、`package.json`、`.py`、对应 shebang，或 `Package.swift` 依赖 Node / Python / Electron / PythonKit，脚本失败。`scripts/make-app-icon.py` 是维护用脚本，不在这三份目录里，不打进 App。
