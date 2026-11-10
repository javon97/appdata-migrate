---
name: appdata-migrate
description: Windows C 盘 AppData 瘦身：只读扫描占用、把大目录迁到 D 盘等其它盘并原地建目录联接（Junction），含迁移脚本、校验与回滚。用户说 C 盘满了、AppData 太大、要把软件缓存/数据搬到别的盘时使用。
---

# AppData 迁移（C 盘瘦身）

把 `%LOCALAPPDATA%` / `%APPDATA%` 下的大目录移到其它盘，原路径建目录联接（Junction），程序无感知。适用于 Windows 10/11 单用户机器。

## 边界

- 只处理当前用户 `AppData` 下的目录，不碰 `C:\Windows`、`Program Files`、系统还原。
- 目标盘不能是 C 盘，默认 D 盘，可用 `-TargetDrive` / `-TargetRoot` 选择其它盘或目录。
- 不删除用户文件：搬迁 = 移动 + 建联接；回滚 = 删联接 + 把数据移回。
- 动手前必须让用户确认范围（列出目录清单和体积），并关闭对应程序。
- 搬迁后软件卸载重装、手动改动目标盘目录都可能让联接失效，需要复查。

## 流程

### 1. 只读扫描

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-appdata.ps1 -Top 30
```

输出 `AppData\Local`、`AppData\Roaming`、`AppData\LocalLow` 各顶层子目录体积，已联接的目录标 `[联接]` 且不计入 C 盘占用；同时显示 C/D 可用空间。

### 2. 选范围，分三档

| 档位 | 对象 | 风险 |
| --- | --- | --- |
| 配置级 | npm / pip / uv 缓存 | 最低，改配置指向新路径即可 |
| 目录联接 | 纯缓存、更新器目录、聊天记录、草稿数据 | 低，关程序后搬 |
| 谨慎 | 程序安装目录（如 `Local\Feishu`） | 中，大版本更新可能重建目录 |

给用户 2–3 个范围方案（稳妥 / 推荐 / 加强），写明各自能释放多少 GB，由用户选，不要替用户决定。

### 3. 关程序

`Get-Process` 核对目标程序是否在跑（含托盘进程）。优先让用户自己关；被锁定的文件强搬会失败或损坏数据。

### 4. 搬迁

单个目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 -Path "C:\Users\<user>\AppData\Local\X" -WhatIf   # 先预演
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 -Path "C:\Users\<user>\AppData\Local\X"
```

默认目标 `D:\AppDataMoved\<相对路径>`；换盘用 `-TargetDrive E`（等价 `-TargetRoot "E:\AppDataMoved"`），也可用 `-TargetRoot` 指定任意目录。不指定且 D 盘不存在时会报错并列出可用盘符。

脚本会拒绝把目标放在 C 盘，并校验目标盘剩余空间 ≥ 待搬体积 ×1.05（确认要试可加 `-Force`）。流程：校验路径在 AppData 内 → 计算体积 → `Move-Item` → `New-Item -ItemType Junction` → 校验 `LinkType` → 汇报释放空间。

批量搬迁时逐个目录调用、每个单独 try/catch，一个失败不影响其它。

### 5. 校验

- `(Get-Item $path).LinkType` 应为 `Junction`
- `Get-ChildItem $path` 能看到原内容
- C 盘可用空间确实增加
- 让用户打开程序确认：微信聊天记录在、剪映草稿能打开、飞书不需要重新配置

### 6. 回滚

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 -Path "C:\Users\<user>\AppData\Local\X" -Rollback
```

先删联接（只删链接，不删 D 盘数据），再把数据移回原路径。回滚前必须关闭程序。

## 已知坑（2026-11 实测）

- 微信数据在 `Roaming\Tencent\xwechat`，不是旧版的 `WeChat Files`。
- 飞书大头在 `Roaming\LarkShell\aha`（约 9 GB），程序目录在 `Local\Feishu`，两者分开。
- Chrome 缓存在 `Local\Google\Chrome\User Data\Default\Cache`、`Code Cache`、`Service Worker`；`Local\Google` 还含程序，不要整目录搬。
- 剪映草稿回收站 `User Data\Projects\com.lveditor.draft\.recycle_bin` 可能拒绝移动：先 `takeown /f <路径> /r /d y` 再 `icacls <路径> /grant Administrators:F /t`；仍失败就把父目录改名 `X_leftover`，在原路径建联接，残留通常只有几 KB。
- `Move-Item` 中途失败会留下「源剩一部分、目标已有一部分」的半搬状态：逐个子目录重试，目标已存在的跳过，补齐后再建联接。
- npm 缓存除建联接外，还应 `npm config set cache <D 盘路径>`；pip 用 `pip config set global.cache-dir <D 盘路径>`。
- `*-updater` 目录（kimi / chatcut / genieworkbuddy / deepseek 等）是安装包缓存，可直接搬。
- 扫描脚本必须跳过 ReparsePoint，否则会把 D 盘数据算成 C 盘占用。
- `Local\Temp` 属于清理不属于搬迁，程序运行中不要搬。

## 交付

- 汇报：释放前后 C 盘可用空间、每个目录大小、联接校验结果、遗留项。
- 提醒：卸载重装后联接可能失效；建议每季度重跑一次扫描看新增占用。
