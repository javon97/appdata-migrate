# appdata-migrate

Windows C 盘瘦身工具：把 `AppData` 下的大目录迁到其它盘，在原路径建立目录联接（Junction），程序仍按原路径读写，无感知。

配套一个只读扫描脚本，先看清谁在占空间，再决定搬什么。

## 内容

| 文件 | 作用 |
| --- | --- |
| `SKILL.md` | 给 Claude Code 等支持 SKILL.md 的 Agent 用的技能说明 |
| `scripts/scan-appdata.ps1` | 只读扫描 AppData 各目录体积，跳过已迁移的联接 |
| `scripts/migrate-folder.ps1` | 单目录搬迁、建联接；支持 `-WhatIf` 预演与 `-Rollback` 回滚 |

## 安装

```bash
git clone https://github.com/javon97/appdata-migrate.git
cp -r appdata-migrate ~/.claude/skills/appdata-migrate
```

Windows 上也可以用资源管理器把整个仓库复制到 `%USERPROFILE%\.claude\skills\appdata-migrate`。

## 使用

### 1. 只读扫描

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-appdata.ps1 -Top 30
```

输出 `AppData\Local`、`AppData\Roaming`、`AppData\LocalLow` 各顶层目录体积、已迁移联接和 C/D 可用空间；加 `-ReportDir <目录>` 可同时保存报告。

### 2. 预演

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 `
  -Path "C:\Users\<user>\AppData\Local\SomeApp" -WhatIf
```

### 3. 搬迁

先关闭对应程序，再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 `
  -Path "C:\Users\<user>\AppData\Local\SomeApp"
```

默认目标为 `D:\AppDataMoved\<路径>`，可用 `-TargetRoot` 修改。脚本会移动目录、在原路径建 Junction 并校验。

### 4. 回滚

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/migrate-folder.ps1 `
  -Path "C:\Users\<user>\AppData\Local\SomeApp" -Rollback
```

删除联接（不动数据）并把目录移回原位置，执行前需关闭程序。

## 边界

- 只操作当前用户 `AppData` 下的目录，不碰系统目录。
- 不删除用户文件：搬迁是移动 + 建联接，回滚是删联接 + 移回。
- 需要关闭目标程序，否则可能因文件占用中途失败。
- 软件卸载重装、手动改动目标盘目录都可能让联接失效，需要复查。
- `Local\Temp` 属于清理不属于搬迁。

## 已知坑

- 微信数据在 `Roaming\Tencent\xwechat`；飞书大头在 `Roaming\LarkShell\aha`。
- Chrome 缓存要单独搬 `User Data\Default\Cache`、`Code Cache`、`Service Worker`，不要整搬 `Local\Google`。
- 剪映草稿回收站可能拒绝移动，需先 `takeown` + `icacls`，或把父目录改名后在原路径建联接。
- 扫描脚本会跳过 ReparsePoint，避免把其它盘的数据算成 C 盘占用。
- 若 `Move-Item` 中途失败，先对比源和目标、逐个子目录补齐，不要直接重试整目录。

## 说明

- 脚本为 PowerShell，适用于 Windows 10/11。
- 目录联接（Junction）不需要管理员权限，但创建前需确保目标路径不存在。
