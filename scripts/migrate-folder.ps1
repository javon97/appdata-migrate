<#
.SYNOPSIS
  把当前用户 AppData 下的目录搬到其它盘，并在原路径建立目录联接（Junction）。
.DESCRIPTION
  搬迁: Move-Item 到目标盘 -> New-Item -ItemType Junction -> 校验 LinkType。
  回滚: 删除联接（只删链接，不动目标数据）-> 把数据移回原路径。
  只允许操作 %USERPROFILE%\AppData 下的目录。
.PARAMETER Path
  源目录（搬迁）或联接路径（回滚），必须在 AppData 下。
.PARAMETER TargetDrive
  目标盘符，如 E: 或 E，等价于 -TargetRoot "E:\AppDataMoved"。
.PARAMETER TargetRoot
  目标根目录。不指定 TargetDrive 时使用；留空则默认 D:\AppDataMoved（D 盘不存在会报错并列出可用盘）。
.PARAMETER Force
  跳过目标盘剩余空间检查（默认要求可用空间 >= 待搬体积 ×1.05）。
.PARAMETER WhatIf
  只打印计划，不做任何修改。
.PARAMETER Rollback
  回滚模式。
.EXAMPLE
  migrate-folder.ps1 -Path "C:\Users\Administrator\AppData\Local\Foo" -WhatIf
.EXAMPLE
  migrate-folder.ps1 -Path "C:\Users\Administrator\AppData\Local\Foo" -TargetDrive E
.EXAMPLE
  migrate-folder.ps1 -Path "C:\Users\Administrator\AppData\Local\Foo" -TargetRoot "E:\Caches"
.EXAMPLE
  migrate-folder.ps1 -Path "C:\Users\Administrator\AppData\Local\Foo" -Rollback
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$TargetDrive = '',
    [string]$TargetRoot = '',
    [switch]$Force,
    [switch]$WhatIf,
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Get-DirSize {
    param([string]$Folder)
    $bytes = [long]0
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Folder)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($dir)) {
                try { $bytes += ([System.IO.FileInfo]$file).Length } catch {}
            }
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                try {
                    $attr = [System.IO.File]::GetAttributes($sub)
                    if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    $stack.Push($sub)
                } catch {}
            }
        } catch {}
    }
    return $bytes
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    return ('{0:N0} MB' -f ($Bytes / 1MB))
}

function Get-FixedDriveNames {
    return @([System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
        ForEach-Object { $_.Name.Substring(0, 2) })
}

$appDataRoot = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'AppData'))
$full = [System.IO.Path]::GetFullPath($Path)

if (-not $full.StartsWith($appDataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝操作：$full 不在 $appDataRoot 下。"
}

$item = Get-Item -LiteralPath $full -Force
$isLink = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)

if ($Rollback) {
    if (-not $isLink) { throw "回滚失败：$full 不是目录联接。" }
    $target = @($item.Target)[0]
    if (-not $target) { throw "读取联接目标失败：$full" }
    Write-Host ('回滚: ' + $full)
    Write-Host ('数据在: ' + $target)
    if ($WhatIf) { Write-Host '[预演] 将删除联接并把数据移回，未执行。'; return }
    $answer = Read-Host '确认回滚？请先关闭相关程序 (y/N)'
    if ($answer -ne 'y') { Write-Host '已取消。'; return }
    [System.IO.Directory]::Delete($full, $false)
    Move-Item -LiteralPath $target -Destination $full
    Write-Host ('完成。数据已移回 ' + $full)
    return
}

if ($isLink) { throw "$full 已经是目录联接，无需搬迁。" }
if (-not $item.PSIsContainer) { throw "$full 不是目录。" }

$size = Get-DirSize -Folder $full

if ($TargetDrive) {
    $letter = $TargetDrive.Trim().TrimEnd('\').TrimEnd(':').ToUpper()
    if ($letter -notmatch '^[A-Z]$') { throw "盘符格式不对：$TargetDrive（示例：E: 或 E）" }
    $driveRoot = $letter + ':\'
    if (-not (Test-Path -LiteralPath $driveRoot)) {
        throw ('磁盘不存在：' + $driveRoot + '。可用盘符：' + ((Get-FixedDriveNames) -join ' '))
    }
    $TargetRoot = $driveRoot + 'AppDataMoved'
}

if (-not $TargetRoot) {
    if (Test-Path -LiteralPath 'D:\') {
        $TargetRoot = 'D:\AppDataMoved'
    } else {
        throw ('未指定目标盘，且默认 D 盘不存在。请用 -TargetDrive 指定，可用盘符：' + ((Get-FixedDriveNames) -join ' '))
    }
}

$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$targetRootDrive = [System.IO.Path]::GetPathRoot($TargetRoot)
if ($targetRootDrive -match '^([A-Za-z]):\\$') {
    $targetLetter = $Matches[1].ToUpper()
    if ($targetLetter -eq 'C') { throw '拒绝把目标放在 C 盘。' }
    $driveInfo = New-Object System.IO.DriveInfo($targetLetter)
    if (-not $driveInfo.IsReady) { throw ('目标盘不可用：' + $targetLetter + ':') }
    $required = [long]($size * 1.05)
    if ($driveInfo.AvailableFreeSpace -lt $required -and -not $Force) {
        throw ('目标盘剩余空间不足：需要 ' + (Format-Size $required) + '，可用 ' + (Format-Size ([long]$driveInfo.AvailableFreeSpace)) + '。确认要试可加 -Force。')
    }
}

$relative = $full.Substring($appDataRoot.Length).TrimStart('\')
$leaf = ($relative -replace '[\\/:*?"<>|]', '_')
$targetPath = Join-Path $TargetRoot $leaf

Write-Host ('源目录: ' + $full)
Write-Host ('体积:   ' + (Format-Size $size))
Write-Host ('目标:   ' + $targetPath)

if ($WhatIf) { Write-Host '[预演] 未做任何修改。'; return }
if (Test-Path -LiteralPath $targetPath) { throw "目标已存在：$targetPath" }

$freeBefore = [long](Get-PSDrive -Name C).Free
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

try {
    Move-Item -LiteralPath $full -Destination $targetPath
} catch {
    throw ("搬迁中断：" + $_.Exception.Message + "`n源目录可能只搬走一部分。不要直接重试整目录，先对比源和目标，逐个子目录补齐；仍被占用可把源目录改名后在原路径建联接。详见 SKILL.md 已知坑。")
}

New-Item -ItemType Junction -Path $full -Target $targetPath | Out-Null

$check = Get-Item -LiteralPath $full -Force
if ($check.LinkType -ne 'Junction') { throw "联接创建失败：$full" }

$freeAfter = [long](Get-PSDrive -Name C).Free
Write-Host ('完成。C 盘可用 ' + (Format-Size $freeBefore) + ' -> ' + (Format-Size $freeAfter) + '（释放 ' + (Format-Size ($freeAfter - $freeBefore)) + '）')
Write-Host '请打开对应程序确认数据正常；卸载重装后需复查联接是否还在。'
