# 附件流式读写

状态：生效
建立：2026-11-10

产品规则见 `docs/ATTACHMENTS.md`。数字天花板来自 `docs/PERF-BUDGET.md`（该文件另分支落地，本文件直接引用同一组数）。

标识符保持英文，和代码里的类型一致。

## 天花板

| 项 | 天花板 | 代码 |
|---|---|---|
| 软上限 | 10GB | `StreamingBudget.softCapBytes` = 10 × 1024³ |
| 附件写入峰值 RAM | **小于 32MB**，且不随文件变大 | `StreamingBudget.writePeakBytes` = 32 × 1024²。比较用 `<` |
| 打开带 10GB 附件的文档 | 进程 RAM 增量 **小于 50MB** | `StreamingBudget.openRamDeltaBytes` = 50 × 1024²。比较用 `<` |
| 缩略图磁盘缓存 | **≤ 200MB**，LRU | `StreamingBudget.thumbnailCacheBytes` = 200 × 1024²。比较用 `≤` |

单次 I/O 块是 `StreamingBudget.chunkBytes`（1MB）。一块远小于 32MB。写入路径同一时刻只留这一块可复用缓冲区，外加 SHA-256 / CRC-32 的固定状态和 ZIP 局部头。附件正文不进 `Data` 的整包，也不按文件长度 `reserveCapacity`。

`document.json` 是导图本身，不是附件。它仍受打开路径的物化上限约束：中央目录 + `document.json` + `metadata.json` 的驻留总和必须小于 50MB。附件字节不计入这份驻留。

## 流式写入

插入在用户确认之后才发生（确认本身只 `stat` 文件长度，见下文）。

1. 以 `chunkBytes` 从源文件随机读，更新 `SHA256Streaming` 和 `CRC32Streaming`，块用完即丢。
2. sha256 已在包内则不去重写入正文，只把引用记到节点上。
3. 否则把现有 ZIP 的局部文件区按块拷到临时文件（已有附件也是一块一块拷，不整段读入），再按块写入新条目，最后写中央目录和 EOCD。
4. `replaceItem` 换回目标路径。读者先关掉，再替换。

压缩方法固定为 0（stored）。压缩后大小等于原大小。不转码、不改封装。sha256 只用于去重和完整性，不作为重新编码的理由。条目名是 `assets/<sha256>.<ext>`。

体积或偏移放不进 32 位时用 ZIP64 extra（header id `0x0001`）、ZIP64 EOCD 和 locator。这样 10GB 软上限内的单文件和整包都能写。软上限不是内存策略：超过 10GB 仍走同一条流，确认文案会写明已超过软上限。

导出附件是同一条拷贝：从 `dataOffset` 起按块写到目标文件，方法必须是 0。导出字节与源文件一致。

## 引用计数与孤儿回收

节点上的 `attachments` 是引用，不是正文。`AttachmentReferences.counts` 按 sha256 计数：同一份字节被多个节点引用时计数大于 1，ZIP 里仍然只有一条 `assets/<sha256>.<ext>`。

保存时重写 ZIP。`assets/` 里 sha256 已经不在任何节点上的条目是孤儿，`AttachmentReferences.orphans` 列出它们，重写时不拷贝。引用还在的附件按块拷贝，不整段读入。去重看 sha256，不看扩展名：同一哈希已在包里就不再写第二份正文。

## ZIP 条目

排序后的名字与现有 `ZipArchive.write` 一致：

| 条目 | 方法 | 正文 |
|---|---|---|
| `assets/<sha256>.<ext>` | 0 | 源文件原字节 |
| `document.json` | 0 | `MindMapDocument` |
| `metadata.json` | 0 | `FlorettaMetadata` |

节点上的 `attachments` 只存引用：`sha256`、`fileExtension`、`byteCount`、`filename`。不存正文。

局部头：version needed 20（ZIP64 时 45），flags 0，method 0，时间 0，CRC-32，大小，名字，需要时再加 ZIP64 extra。不写 data descriptor。

## 打开路径（只读中央目录）

`FlorettaStreamingDocument.open` 不读附件正文。

1. 读文件末尾 22 字节的 EOCD（我们写出的包注释长度为 0）。
2. 若 32 位字段是 `0xFFFFFFFF` / `0xFFFF`，再读它前面的 ZIP64 locator 和 ZIP64 EOCD，拿到真正的中央目录偏移和长度。
3. 按中央目录声明的偏移和长度读取目录本身。目录超过物化预算则拒绝（防畸形目录，不是卡附件体积）。
4. 对每个条目只读局部头（30 字节 + 文件名 + extra），算出 `dataOffset`。`assets/` 到此为止：记下 `byteCount`、`crc32`、偏移，不读 `[dataOffset, dataOffset + byteCount)`。
5. 只把 `document.json` 和 `metadata.json` 的正文读进来。方法必须是 0。加密或 data descriptor（flag bit 0 / bit 3）拒绝。

因此打开 10GB 附件时，进程新增的只是目录和两份 JSON，增量小于 50MB。完整性校验不在打开时做；要对正文做 sha256，走单独的按块校验，不进打开路径。

`ZipContainer.read(data:)` 仍是小包的内存 API，会把已经在 `Data` 里的条目解出来，并保留原来的条目数 / 32MB 解压限制。那不是产品打开路径，也不是 10GB 附件的上限。产品打开和插入走 `FlorettaStreamingDocument`。

## 缩略图

磁盘目录：`Application Support/Floretta/Attachments/thumbnails/`。最长边 `StreamingBudget.thumbnailLongestEdge`（256）。这是降采样后的小图，不是原图。

流水线是 `ThumbnailPipeline.materialize`：

1. `FlorettaStreamingDocument.exportAttachment` 把 ZIP 条目按块写到 `Attachments/spill/<sha256>`。附件正文不进一个 `Data`。
2. `ThumbnailDecodingPort.downsample(spill:longestEdge:)` 只打开这个 spill 文件。Apple 适配器是 `ImageIOThumbnailDecoder`：`CGImageSourceCreateWithURL` + `kCGImageSourceThumbnailMaxPixelSize`，再写成 PNG。
3. PNG 写入 `ThumbnailFileCache`（LRU）。然后删掉 spill。

视口是 `AttachmentThumbnailMemory`，内部用 `ThumbnailMemory`：

1. 节点矩形与视口不相交：不解码。已在内存里的 `CGImage` 卸掉。磁盘上的缩略图还在。
2. 进入视口：磁盘命中则把小 PNG 读成 `CGImage` 并画在节点上。
3. 未命中且扩展名是图片：走上面的 spill → ImageIO → 磁盘缓存。生成过程中若节点已经滚出视口，结果只留在磁盘，不放进内存。
4. 非图片：不生成缩略图。节点上仍显示大小。

LRU：`ThumbnailDiskBudget.victims` 按 `lastUsed` 从旧到新丢弃，直到 `≤ thumbnailCacheBytes`（200MB）。新的一张若本身大于上限，拒绝写入缓存，不把缓存撑破。

## iCloud

排除的是应用支持目录里的 `Attachments`（含 `thumbnails` 和 `spill`），不是用户自己的 `.floretta`。

`AttachmentDirectory.prepare` 创建这三层目录后调用 `BackupExclusionPort.excludeFromBackup`。Apple 适配器写 `URLResourceValues.isExcludedFromBackup = true`。设备备份因此不会收走缩略图和 spill。文档若在 iCloud Drive，仍按用户的文件同步，那是另一回事。

## 确认

`AttachmentInsertProposal` 只吃两个长度：源文件的 `fileSize`，以及当前 `.floretta` 的逻辑大小。不读正文、不算 sha256、不压缩。

`projectedDocumentByteCount` = 两者之和（饱和加法）。这是去重前的上界；字节若已在包里，实际文件不会再长这么多。

文案三行，外加超限时的第四行：

- `文件大小：…`
- `放入后文档大约：…`
- `字节原样放进当前项目，不压缩、不转码。`
- 任一长度 `> softCapBytes` 时加 `超过 10GB 软上限。`

界面用非阻塞的确认（SwiftUI `confirmationDialog`）。取消不写盘、不改节点。点「放入」之后才在后台按块哈希并写入。哈希和拷贝不占主线程。
