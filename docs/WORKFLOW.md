# 工作流：分步提交、每步推送

Timmy 的硬要求：**每做完一步、每更新一次版本都要上传。** 不允许攒着。

## 提交粒度

一个"步"= 一个能独立验收的小改动，对应 `TASKBOOK-001.md` 里的 `P0-1`、`P1-3` 这种编号。

```
P1-3: keyboard model (Tab child, Enter sibling, arrow nav)
```

- 一处逻辑改动 + 对应测试 = 一个提交。
- 不许出现 "wip"、"fix stuff"、"update" 这类无法验收的信息。
- 大重构前先提交一次可运行状态，再动刀。

## 每步的动作

```bash
git add -A
git commit -m "P1-3: keyboard model" -m "做了什么 / 没做什么 / 怎么验证"
git push origin main
```

只有 push 成功才算这一步完成。**push 失败不许继续做下一步**，先报告。

## 分支

- 单人开发直接推 `main`，不搞花活。
- 只有在实验性重构（可能推翻）时才开 `experiment/<名字>`，验收前不合入。

## 验收由总指挥做

性能按 `docs/PERF-BUDGET.md`。新功能提案先对预算，不许「以后再优化」。PR 描述要有三行「性能影响」（内存 / 帧率 / 包体各一行），缺一行即阻断。

版本与安装按 `docs/HANDOFF.md` 第 29 条：验收只走 TestFlight，不用 Xcode 装进 `/Applications`，本机不叠多份 1.0 (3)/(4)/(5)；只留一套可运行构建，旧 archive 与 DerivedData 进废纸篓而不是 `rm`；每一轮测试组只留最新构建，旧构建移出测试组但不删 App Store Connect 记录；`CURRENT_PROJECT_VERSION` 递增，`MARKETING_VERSION` 不动。

执行者说"完成"只算申报。总指挥会独立检查：

| 它说 | 查什么 |
|---|---|
| 构建通过 | 自己跑 `xcodebuild` / 看产物时间戳 |
| Tab/Enter 好用 | 自己在 Mac 上连续录入一段真实中文内容 |
| 内存/帧率达标 | 自己取 footprint 与实测帧率，写进 `docs/measure.md` |
| 支持某格式 | 用真实样本往返，看导出文件在对方软件里能否打开 |

## 与总指挥的沟通

- 卡住 > 30 分钟：写 `docs/STATUS.md`（卡在哪/试过什么/要什么决定），停下等。
- 不许自己降级需求（原生→WebView、三端→只做 Mac）。
- 新增第三方依赖：先在 `docs/STATUS.md` 写理由，等许可。
