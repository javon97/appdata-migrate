<#
.SYNOPSIS
  只读扫描 Windows AppData 目录占用，输出体积排行。
.DESCRIPTION
  扫描 %LOCALAPPDATA%、%APPDATA%、AppData\LocalLow 的顶层子目录，跳过目录联接
  （ReparsePoint），不修改任何文件。结果可同时写入报告文件。
.PARAMETER Top
  显示前 N 项，默认 30。
.PARAMETER MinMB
  只显示不小于该体积（MB）的目录，默认 20。
.PARAMETER ReportDir
  指定后把结果写入该目录下的 AppData扫描_yyyy-MM-dd.txt。
#>
param(
    [int]$Top = 30,
    [int]$MinMB = 20,
    [string]$ReportDir = ''
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

function Get-DirSize {
    param([string]$Path)
    $bytes = [long]0
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Path)
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

$roots = @(
    @{ Label = 'Local';    Path = $env:LOCALAPPDATA },
    @{ Label = 'Roaming';  Path = $env:APPDATA },
    @{ Label = 'LocalLow'; Path = (Join-Path $env:USERPROFILE 'AppData\LocalLow') }
)

$rows = New-Object System.Collections.Generic.List[object]
$grand = [long]0

foreach ($root in $roots) {
    if (-not $root.Path -or -not (Test-Path -LiteralPath $root.Path)) { continue }
    Get-ChildItem -LiteralPath $root.Path -Directory -Force | ForEach-Object {
        $entry = $_
        $isLink = (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isLink) {
            $target = ''
            try { $target = @($entry.Target)[0] } catch {}
            $rows.Add([pscustomobject]@{ Root = $root.Label; Name = $entry.Name; Bytes = [long]0; Link = $true; Target = $target })
            return
        }
        $size = Get-DirSize -Path $entry.FullName
        $grand += $size
        $rows.Add([pscustomobject]@{ Root = $root.Label; Name = $entry.Name; Bytes = $size; Link = $false; Target = '' })
    }
}

$driveParts = @()
foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -eq 'Fixed' -and $drive.IsReady) {
        $driveParts += ($drive.Name.Substring(0, 2) + ' 可用 ' + (Format-Size ([long]$drive.AvailableFreeSpace)))
    }
}
$freeLine = '磁盘: ' + ($driveParts -join '   ')

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('AppData 占用扫描  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
$lines.Add($freeLine)
$lines.Add('说明: [联接] 为已迁移目录，数据在其它盘，不计入合计。')
$lines.Add(('-' * 72))
$lines.Add(('{0,-8} {1,-42} {2}' -f '位置', '目录', '体积'))

$shown = $rows | Where-Object { -not $_.Link -and $_.Bytes -ge ($MinMB * 1MB) } | Sort-Object Bytes -Descending | Select-Object -First $Top
foreach ($row in $shown) {
    $lines.Add(('{0,-8} {1,-42} {2}' -f $row.Root, $row.Name, (Format-Size $row.Bytes)))
}

$links = $rows | Where-Object { $_.Link -and ($_.Target -notlike '*\AppData\*') } | Sort-Object { $_.Root + $_.Name }
if ($links.Count -gt 0) {
    $lines.Add('')
    $lines.Add('已迁移（联接，数据在其它盘）:')
    foreach ($row in $links) {
        $lines.Add(('{0,-8} {1,-42} {2}' -f $row.Root, $row.Name, '-> ' + $row.Target))
    }
}

$lines.Add(('-' * 72))
$lines.Add('合计（不含联接）: ' + (Format-Size $grand))
$lines.Add('提示: 目录联接不占 C 盘；如需搬迁，按 appdata-migrate 技能执行。')

$text = ($lines -join [Environment]::NewLine)
Write-Host $text

if ($ReportDir) {
    try {
        if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
        $reportPath = Join-Path $ReportDir ('AppData扫描_' + (Get-Date -Format 'yyyy-MM-dd') + '.txt')
        [System.IO.File]::WriteAllText($reportPath, $text, (New-Object System.Text.UTF8Encoding $true))
        Write-Host ''
        Write-Host ('报告已保存: ' + $reportPath)
    } catch {
        Write-Host ('报告写入失败: ' + $_.Exception.Message)
    }
}
