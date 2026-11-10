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
