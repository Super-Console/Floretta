# Floretta 仓库工作约定（给所有 AI agent 读）

## 目录结构

```
~/AWS/floretta/                    ← 仓库根，唯一工作区
  .worktrees/<name>/               ← 并行任务的 git worktree（已 gitignore）
  .dispatch/                       ← 任务书与 DONE 文件（已 gitignore，不入库）
```

**不要在仓库外新建工作目录。** 非交互会话里 `external_directory` 权限是 `ask`，会被直接拒绝，表现为“权限坏了”。

## 并行规则

- 每个 agent / 每个任务用**自己的 worktree 和独立分支**：
  `git worktree add -b <branch> .worktrees/<name> origin/main`
- 不要把两个 agent 指向同一个 worktree。
- 任务结束不需要保留 worktree 时，用 `git worktree remove .worktrees/<name>`。
- 文件面不要重叠：UI 与工程配置（pbxproj / plist）分开改，改前先确认另一个 agent 没在碰同一批文件。

## 验证分工

- **无人值守 SSH 会话无法签名构建**：带扩展（Share / Quick Look）的 target 会因钥匙串不可用报 `errSecInternalComponent`，加 `CODE_SIGNING_ALLOWED=NO`、`ENABLE_DEBUG_DYLIB=NO` 都绕不过。
- 所以：SSH 侧只做结构验证 —— `plutil -lint`、`xcodebuild -showBuildSettings`、`xcodebuild -list`、`swift test`（FlorettaCore）。
- 真正的签名构建 / 归档 / 上传，由 Mac 图形会话中的 agent（或本人在场时）执行。

## 合入规则

- 每个 PR 必须有：性能三行（内存 / 帧率 / 包体）、受影响模块的测试、双端编译。
- Censor 通过才合；合入由 Hermes 或项目负责人执行。
- 合入前确认 PR head 就是被审查通过的那个 commit，不要合过期 tip。

## 命名

- 仓库与工作区统一叫 `floretta`（旧名 `Supernode` 已废弃，仅存于历史提交与远程仓库名）。

## 文档更新规则（重要）

PR **不要**修改这四个共享文档：

```
docs/FEATURES-CHECKLIST.md
docs/STATUS.md
docs/SMOKE.md
docs/VERIFY.md
```

原因：每个 PR 都往同一批行里追加记录，rebase 时必然冲突（实测 5 个冲突里 4 个出在这里），而且冲突是语义性的，无法机械解决。

正确做法：
- 需要记录完成项时，在 PR 描述里写清楚「要往检查单哪一节加哪一行」
- 合并后由单一写者（Hermes / Censor）统一更新这些文档
- rebase 撞上这些文档的冲突，直接取 `main` 版本，只保留代码改动

## 资源收尾（硬规则）

任何用到模拟器、模拟进程、后台服务的任务，**结束时必须收尾**，不能把资源留在机器上：

1. iOS / iPadOS 模拟器：任务结束执行 `xcrun simctl shutdown all`，并在报告里附 `xcrun simctl list devices booted | grep -c Booted` 的结果（必须是 0）
2. 后台起的 `xcodebuild`、`opencode serve`、测试服务：确认进程已退出（`pgrep` 为空）
3. 临时 DerivedData 目录（`/tmp/xxx-dd`）超过 1 个的，任务结束后清理自己创建的那些
4. 报告里写一行「资源收尾：模拟器已关 / 后台进程已退 / 临时目录已清」，**没有这一行视为任务未完成**

原因：一台机器同时跑两台模拟器会吃掉数 GB 内存，用户会立刻感知到卡顿；而这些资源不会自己退出。

$'
## 临时规则（2026-11-11 起）：GUI 测试只在副屏

用户在主屏（QSN-CAB，5120×2880）上工作期间，所有 GUI 自动化与截图**必须**在副屏 （竖屏 2880×5120，坐标 x ≥ 2560）上进行：

1. 启动被测 App 后先把窗口移到副屏，再操作与截图
2. 禁止在主屏调用 bring_to_front、禁止 Cmd+Tab 抢焦点、禁止连续快速切窗口
3. 操作间隔 ≥ 2 秒，避免打断用户输入
4. 结束立刻关闭测试实例
5. 报告里写一行「GUI 操作已在副屏完成，主屏未被打扰」

此条为**临时规则**，用户取消后失效。

## 长任务监督：后台 + 终态判据（2026-11-11 起）

1. 预计超过 15 分钟的活，**后台脱离式启动**，不在对话里用模型 sleep 轮询；5 分钟以内直接前台跑，不建监视。
2. 终态判据必须可机器校验，并按三种结局给退出码：`0` 成功且产物完整 / `2` 进程退出但产物不完整 / `3` 超时（硬上限 2–3 小时）。**“文件已生成”不算完成。**
3. **一任务一监视一产物文件**：不同任务绝不共用监视，也绝不写同一个输出文件（并发追加会互相覆盖）；同一任务的多个子步骤合并成一个监视。
4. 轮询间隔 ≥ 45 秒，必须设硬超时；唤醒后自己读产物与 `git log` 验收，不采信 agent 自报。
5. **一次性脚本只能放 `/tmp/<task>-runners/` 或 `mktemp -d`**，禁止落在本仓库、`~/AWS/scripts`、桌面、Downloads；任务结束立即删临时目录与临时日志；长期复用只保留通用壳（`run-oc-task.sh` / `run-oc-continue.sh`）；收尾扫 `/tmp`，清掉 24 小时以上残留。
