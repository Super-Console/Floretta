# 清理盘点清单

> **这份清单只做记录，不执行任何删除；删除须用户本人确认。** 本文是 2026-11-11 的现场快照；大小由 `du -sh` 读取，后续可能变化。没有可靠身份/用途判断的对象按用户数据保护规则标为保留，不因“构建产物”名称直接删除。

## I6 · TestFlight 旧构建

### 能查到的状态

- 本环境没有可用的 App Store Connect 构建列表/API 凭据；因此**不能实时读取 TestFlight 当前所有 build 号及处理状态**，本节不伪造完整列表。
- 本仓库 `docs/FEATURES-CHECKLIST.md` 的历史阻塞记录写有 `1.0 (1)` 仍在 Beta 审核队列、阻碍新 build 外部测试审核；记录日期约为该清单会话 2026-11-09 至 11-10，**不是当前 App Store Connect 状态**。
- 当前工程文件配置是 Marketing Version `1.0`、`CURRENT_PROJECT_VERSION = 10`；这仅说明源码配置，不证明 build 10 已上传或其 TestFlight 状态。
- 本地归档存在 `Floretta-iOS-1.0.10.xcarchive`（40M），只是本机归档文件，不能据此推断已上传/可测试。

| Build / 版本 | 状态 | 依据 | 建议 |
|---|---|---|---|
| 1.0 (1) | 历史记录称 Beta 审核队列中；当前状态未核实 | `docs/FEATURES-CHECKLIST.md` 历史阻塞 | 暂保留；用户本人登录 App Store Connect 核验后决定 |
| 1.0 (10) | 未核实是否上传及状态 | 当前 Xcode 工程版本值，不是 ASC 记录 | 暂保留/待核验；不据此判断可删 |
| 其他 build | 未能实时枚举 | 当前环境无 ASC 列表权限 | 需用户本人从 ASC 导出完整 build 列表后补录 |

**操作边界：旧 TestFlight 构建由用户本人在 App Store Connect 操作，Hermes 不代为删除。** 删除前应确认 build、测试组、审核状态及回退需求；不清空或撤下任何构建。

## I7 · 工作区旧构件

### `~/AWS/floretta/build/`（总计 3.9G）

当前仓库根 `/Users/TimmySheep/AWS/floretta/build/` 顶层项目与实测大小：

| 路径（相对 build） | 大小 | 初步处置建议 |
|---|---:|---|
| `dual-verify/` | 753M | **必须保留**：测试日志、结果包、截图及验证材料；其中含验收证据。 |
| `dd-macos-archive-10/` | 853M | 暂保留；DerivedData 类构建材料，待确认相关归档/验证已结束后再由用户决定。 |
| `dd-macos-archive/` | 815M | 暂保留；同上。 |
| `dd-macos-tf11/` | 449M | 暂保留；名称涉及 TF11，需确认当前发布链路依赖。 |
| `dd-ios-archive-10/` | 271M | 暂保留；待确认归档链路完成。 |
| `dd-ios-archive/` | 265M | 暂保留；待确认归档链路完成。 |
| `Floretta-macOS-1.0.10.xcarchive/` | 151M | **保留**：发布归档，不能当普通缓存清理。 |
| `Floretta-macOS.xcarchive/` | 132M | 暂保留；须确认是否为当前有效归档/唯一可回退副本。 |
| `Floretta-iOS-1.0.10.xcarchive/` | 40M | **保留**：发布归档；上传/回退状态未核验。 |
| `Floretta-macOS-prev-1.0.8-20261110-162247.xcarchive/` | 41M | **候选待核验**：旧版本归档；先确认不是唯一回退/签名材料。 |
| `Floretta-macOS-prev-20261110-162123.xcarchive/` | 41M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-macOS-prev-20261110-155458.xcarchive/` | 36M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-macOS-prev-20261110-061058.xcarchive/` | 29M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-iOS-prev-1.0.8-20261110-162208.xcarchive/` | 21M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-iOS-prev-20261110-162123.xcarchive/` | 21M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-iOS-prev-20261110-155458.xcarchive/` | 18M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `Floretta-iOS-prev-20261110-061058.xcarchive/` | 15M | **候选待核验**：旧归档，身份与保留用途需核对。 |
| `xmind-ipad-ref-xfer/` | 3.9M | **必须保留**：参考截图/资料，不是可识别缓存。 |
| `dd-ios-tf11/` | 7.8M | 暂保留；检查其 SourcePackages/索引资料是否仍被 TF11 构建引用。 |
| `rss-probe/` | 8.0K | 用途未核实，暂保留。 |
| `ExportOptions-TestFlight.plist` | 4.0K | **必须保留**：发布配置。 |
| `upload-testflight.sh` | 4.0K | **必须保留**：发布脚本。 |
| `.DS_Store` | 8.0K | 可由用户考虑清理；当前不执行。 |
| `export/`、`export-ios/`、`export-ios-1.0.10/`、`export-macos/`、`export-macos-1.0.10/` | 各 0B | 空目录；可候选清理，但仍须用户确认。 |

> 表中顶层大小不代表可删；`build/` 内历史日志、验证结果、配置、截图和归档均可能承载证据或回退价值。任何处理前需再检查具体内容与依赖关系。

### `~/Library/Developer/Xcode/DerivedData/Floretta-*`

现场共列出 14 个匹配目录。名称带分支/构建语义的目录以及匿名哈希目录均先**保留待核验**；不得批量删除。

| 目录名 | 大小 | 建议 |
|---|---:|---|
| `Floretta-btsdxhacdhlupxdyqlmfarmncdyu` | 126M | 暂保留；用途未知 |
| `Floretta-gffumuervyoomkgpbwzgloamgyax` | 130M | 暂保留；用途未知 |
| `Floretta-gwiojkpyzevroydyagiorhlrvhbn` | 161M | 暂保留；用途未知 |
| `Floretta-dlahgmrqrdaigvbvrfifjoyxstea` | 316M | 暂保留；用途未知 |
| `Floretta-ios-scoped-pr77` | 327M | 暂保留；名称指向 PR 验证材料 |
| `Floretta-eeqrwnfwgsljxjayipsgvlnrrnjn` | 330M | 暂保留；用途未知 |
| `Floretta-ahcmjwnazoyeorbogoqufvbyisza` | 336M | 暂保留；用途未知 |
| `Floretta-ios-tf10` | 339M | 暂保留；发布/构建验证用途需确认 |
| `Floretta-ios-integ-uibatch` | 404M | 暂保留；名称指向集成验证 |
| `Floretta-macos-scoped-pr79` | 468M | 暂保留；名称指向 PR 验证材料 |
| `Floretta-macos-tf10` | 553M | 暂保留；发布/构建验证用途需确认 |
| `Floretta-macos-integ-uibatch` | 589M | 暂保留；名称指向集成验证 |
| `Floretta-macos-scoped-pr77` | 590M | 暂保留；名称指向 PR 验证材料 |
| `Floretta-gqbfxxgxfsnjitgewdjtddpigyxt` | 939M | 暂保留；用途未知，体积大不构成删除依据 |

### `~/AWS/floretta/.worktrees/`

下表对工作树自身目录运行 `du -sh`；**所有目录均必须保留**，因为它们对应现存分支/独立工作任务。不要把活跃 worktree 当构建缓存清理。即使某分支看似已合并，也须先核实状态、未提交内容和负责人，再另行征求用户确认。

| 目录 | 大小 | 状态/处置 |
|---|---:|---|
| `docs` | 18M | 当前文档分支；必须保留 |
| `fix-build` | 215M | `oc/fix-build`；必须保留 |
| `ios-uitest-followup` | 17M | `fix/ios-uitest-followup`；必须保留 |
| `media` | 232M | `oc/media-attachments`；必须保留 |
| `menubar` | 231M | `oc/menu-bar`；必须保留 |
| `pr77-glass` | 17M | detached HEAD；必须保留并先确认归属 |
| `ql-bundleid` | 17M | `oc/ql-bundleid`；必须保留 |
| `rebase` | 17M | `cursor/official-glass-chrome-70a7`；必须保留 |
| `sidebar-thumbs` | 229M | `oc/sidebar-thumbs`；必须保留 |
| `tf10` | 17M | `bump/1.0.10`；必须保留 |
| `tf11` | 18M | `bump/1.0.11`；必须保留 |
| `ui-batch` | 245M | `integration/ui-batch`；必须保留 |

盘点方法：`du -sh` 与 `git worktree list --porcelain`；所有建议都只是后续人工复核入口，不构成删除授权。
