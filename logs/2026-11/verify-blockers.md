# 已知阻塞复核（2026-11-14）

范围：`docs/FEATURES-CHECKLIST.md`「已知阻塞」原有三项。以下记录区分已核实的仓库事实与无法实时核实的外部状态。

## Cursor / Interop 规格文档

- 原表述：Cursor 未授权 `Super-Console/Floretta`，导致 `MD-AS-DOCUMENT`、`FORMAT-FOR-AI`、`FORMATS` 推不上去；要求用户添加仓库授权。
- 结论：**已失效**。此项最早可追溯到 `ea9d48e`（2026-11-09 18:49:03 UTC，`docs: feature checklist for the 2026-11-09/10 session`）首次加入 checklist。Git blame 指向该提交；仓库记录无法进一步识别最初判断对应的会话或日志，也未找到当时的真实 push 错误原文。
- `git ls-files | grep -iE 'MD-AS-DOCUMENT|FORMAT-FOR-AI|FORMATS'` 查到三份文件均已跟踪：`docs/MD-AS-DOCUMENT.md`、`docs/FORMAT-FOR-AI.md`、`docs/FORMATS.md`。
- 三份文件均存在于 `origin/main`。`git log origin/main --oneline -3 -- <文件>` 输出：`MD-AS-DOCUMENT.md`：`5aff21e docs: Markdown-as-Document S0 specs (#32)`；`FORMAT-FOR-AI.md`：`085462c Add AI format spec and verify CI gates and ports`、`24457bb Add canvas regions that enclose nodes without reparenting them.`、`9302261 1.6 便签 (#38)`；`FORMATS.md`：`08e788e Merge branch 'cursor/multi-canvas-sheets-8899' (#86) into integration/ui-batch`、`6a482a1 Add multiple canvases inside one document.`、`24457bb Add canvas regions that enclose nodes without reparenting them.`。各文件最近提交时间分别为：`5aff21e`（2026-11-10 03:03:36 +08:00）、`085462c`（2026-11-11 15:29:28 +08:00）、`08e788e`（2026-11-11 02:41:52 +08:00）。
- 提交 `8340130`（2026-11-09 19:01:56 UTC，`docs: land Markdown-as-Document S0 specs`）已包含三文件，远端 `origin/cursor/md-as-document-s0-4ec4` 可见该提交；之后这些文件也进入 `origin/main`。这至少证明该远端 Cursor 分支曾成功写入，不支持“未授权、推不上去”的说法。
- 未找到可核对的 push 失败记录：检查了仓库文件、`logs/`、`../CM/logs/`、`../CM/incidents/` 中与授权、push 错误及这三份文件有关的内容；还检查了仓库内 `.cursor/`、`~/.cursor/` 和 `~/Library/Logs/` 下名称含 Cursor 的日志文件，未发现授权失败状态或失败原文。Git/文件现状不能证明 Cursor 此刻的账户授权设置；但既然目标提交已经在远端，原阻塞不成立且已失效。
- 原因来源目前只能定位到上述 checklist 初始提交；未找到能确认作者依据或会话 ID 的单独记录。

## App Store Connect 外部测试审核

- 原表述：`1.0 (1)` 仍占 Beta 审核队列，新 build 无法提交外部测试审核。
- 结论：**当前状态未核实，不能继续作为已确认阻塞**。用户提供的当前内测版本是 `1.0 (15)`；它本身不能证明 `1.0 (1)` 的外部测试审核状态。`docs/CLEANUP.md`（2026-11-11 现场快照）明确记录当时环境没有可用 ASC 构建列表/API 凭据，且历史记录不代表当前状态。本次没有 ASC 实时访问证据。
- 新表述为待核实事项：登录 ASC 查 `1.0 (1)` 的外部测试审核状态；若仍在审核且实际阻止新外测提交，再恢复为已确认阻塞。不得把内部测试状态等同外部测试审核状态。

## Python / pip

- 原表述：Python 3.14 无 pip，部分脚本工具受限。
- 本机核实：`python3 --version` 输出 `Python 3.9.6`；`python3 -m pip --version` 输出 `pip 21.2.4`（Xcode Python 3.9 site-packages）；`python3.14 --version` 未找到命令，且检查的 Python 3.14 常见安装目录无结果。
- 结论：当前这台机器上不存在“Python 3.14 无 pip”这一可复现阻塞；从阻塞表移除。没有据此推断所有特定 Python 3.14 脚本兼容 Python 3.9。

## 检查命令与结果摘要

- `git ls-files | grep -iE 'MD-AS-DOCUMENT|FORMAT-FOR-AI|FORMATS'`：三份文件均在版本控制中。
- `git log --oneline -3 -- <文件>`、`git log -1 --format='%h %cI %D %s' -- <文件>`：分别核查三份文件的近期提交及提交时间。
- `git cat-file -e origin/main:<文件>`：三份文件均存在于 `origin/main`；`git ls-remote origin refs/heads/main` 与本地 `origin/main` 指向同一 tip `a4b14b45d4df2ec4ef1721b6d5413d0e43927d09`。
- `git log origin/main --oneline -3 -- <文件>`：上述三份文件的最近提交列表与时间。
- `git blame -L 124,132 -- docs/FEATURES-CHECKLIST.md` 及 `git log --all -S'Cursor 未授权 ...'`：来源定位到 `ea9d48e`。
- `python3 --version`、`python3 -m pip --version`、`python3.14 --version`：结果如上。
- ASC：没有可用实时 ASC 状态证据，本次只记录为待核实，不声称外测队列已释放。
