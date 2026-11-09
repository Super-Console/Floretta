# Web parity

This is the sync contract between Floretta for Mac and Floretta Web. One row per Mac feature. Web status is only `已同步`, `部分`, or `不做`.

Keep this file in step with FlorettaWeb `docs/WEB-PARITY.md` (https://github.com/Super-Console/FlorettaWeb). When Mac adds or changes a feature, update the Mac column and ask Floretta Web to refresh the Web column. Desktop-only capabilities stay `不做` on Web.

Checked against FlorettaWeb PR #5 head `1921840` (branch `cursor/floretta-mac-parity-39f4`). Mac column is the intended desktop app.

| 功能 | Mac | Web | 备注 |
|---|---|---|---|
| 首页（最近文件，先于画布） | ✅ | 已同步 | TASKBOOK-004。桌面是侧栏资料库。小于 720px 是底部「最近 / 新建 / 设置」。 |
| 新建 / 打开 / 另存 .floretta | ✅ | 已同步 | File System Access。Safari 没有该 API 时，用文件选择打开，用下载回写。 |
| Tab 建子节点 / Enter 同级 | ✅ | 已同步 | 中心节点上 Enter 建子节点。 |
| 拖拽重排 | ✅ | 已同步 | 拖到节点上缘或下缘是同级，中间是子级。根节点不能拖走。 |
| 整数缩放八档 | ✅ | 已同步 | 按钮与滚轮：50 / 75 / 100 / 125 / 150 / 200 / 300 / 400。适配会再缩小，以便整图落在画布内。 |
| 大纲视图 | ✅ | 已同步 | 宽 `clamp(200px, 22vw, 280px)`。小于 720px 改为左侧浮层。 |
| 右侧检查器（形状 / 填充 / 文字） | ✅ | 已同步 | 宽 `clamp(240px, 24vw, 320px)`。小于 900px 改为右侧浮层。 |
| 沉浸模式（Zen） | ✅ | 已同步 | 隐藏顶栏、大纲、检查器。Esc 或「离开沉浸」退出。 |
| 导入 .xmind / .opml / .mm / .md | ✅ | 已同步 | `.xmind` 读 `content.json`（fflate）。XMind 8 `content.xml` 只读。关系线等写在 sheet 上的字段导出时原样带回。 |
| 导出 .floretta / .xmind / .md / PNG | ✅ | 已同步 | 全部在浏览器里生成，不上传。 |
| 导出 PDF | ✅ | 部分 | 网页导出的是单页 JPEG 图像 PDF，不是 Mac 打印面板。 |
| 撤销 / 重做 | ✅ | 已同步 | |
| 液态玻璃 | ✅ | 已同步 | 只用在顶栏、大纲、检查器、菜单、底部栏。`backdrop-filter` 可用时不做扁平半透明冒充。不支持时降为 92% 纸色。不铺在画布上。 |
| 自动保存 | ✅ | 已同步 | IndexedDB。`navigator.storage.persist()` 被拒绝时写明可能被系统清理。 |
| 本地文件监听 | ✅ | 不做 | 仅桌面。 |
| 打印面板 | ✅ | 不做 | 仅桌面。 |
| .mmap / .itmz / .smmx / .emmx / .canvas | 见格式矩阵 | 不做 | 本网页版不读这些容器。 |
| MCP | ✅ | 不做 | 介绍页写明：默认只读，写入要确认，一次撤销退回整段写入。网页版没有 MCP。 |
