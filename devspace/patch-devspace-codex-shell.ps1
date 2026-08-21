[CmdletBinding()]
param(
    [string]$TargetPath = "$env:APPDATA\npm\node_modules\@waishnav\devspace\dist\process-platform.js",
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$SupportedPackageName = '@waishnav/devspace'
$SupportedVersion = '1.0.7'
$GitBashPath = 'C:\Program Files\Git\bin\bash.exe'

function Get-OccurrenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )

    $count = 0
    $start = 0
    while ($true) {
        $index = $Text.IndexOf($Needle, $start, [System.StringComparison]::Ordinal)
        if ($index -lt 0) {
            return $count
        }
        $count++
        $start = $index + $Needle.Length
    }
}

if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    throw "Target file not found: $TargetPath"
}

$distDir = [System.IO.Path]::GetDirectoryName($TargetPath)
$packageRoot = [System.IO.Directory]::GetParent($distDir).FullName
$packageJsonPath = Join-Path $packageRoot 'package.json'
if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
    throw "package.json not found: $packageJsonPath"
}

$package = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
if ($package.name -ne $SupportedPackageName -or $package.version -ne $SupportedVersion) {
    throw "Unsupported DevSpace package: $($package.name)@$($package.version). Supported: $SupportedPackageName@$SupportedVersion."
}

if (-not (Test-Path -LiteralPath $GitBashPath -PathType Leaf)) {
    throw "Git Bash not found: $GitBashPath"
}

$content = [System.IO.File]::ReadAllText($TargetPath)
$eol = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }

$officialBlock = [string]::Join($eol, @(
    '    if (platform === "win32") {'
    '        return {'
    '            executable: environment.ComSpec ?? environment.COMSPEC ?? "cmd.exe",'
    '            args: ["/d", "/s", "/c", command],'
    '        };'
    '    }'
))

$patchedBlock = [string]::Join($eol, @(
    '    if (platform === "win32") {'
    '        return {'
    '            executable: "C:\\Program Files\\Git\\bin\\bash.exe",'
    '            args: ["-c", command],'
    '        };'
    '    }'
))

$officialCount = Get-OccurrenceCount -Text $content -Needle $officialBlock
$patchedCount = Get-OccurrenceCount -Text $content -Needle $patchedBlock

if ($officialCount -eq 0 -and $patchedCount -eq 1) {
    Write-Output "DevSpace Codex shell is already patched for Git Bash: $TargetPath"
    exit 0
}

if ($officialCount -ne 1 -or $patchedCount -ne 0) {
    throw "process-platform.js is neither the supported official state nor the known patched state. Refusing to modify it."
}

if ($CheckOnly) {
    Write-Output "DevSpace Codex shell is in the supported official cmd.exe state and can be patched safely: $TargetPath"
    exit 0
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$TargetPath.bak-codex-shell-$timestamp"
Copy-Item -LiteralPath $TargetPath -Destination $backupPath -ErrorAction Stop

try {
    $patchedContent = $content.Replace($officialBlock, $patchedBlock)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($TargetPath, $patchedContent, $utf8NoBom)

    $verify = [System.IO.File]::ReadAllText($TargetPath)
    if ((Get-OccurrenceCount -Text $verify -Needle $officialBlock) -ne 0 -or
        (Get-OccurrenceCount -Text $verify -Needle $patchedBlock) -ne 1) {
        throw 'Post-write verification failed.'
    }
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $TargetPath -Force
    throw "Patch failed and the target was restored from backup. Reason: $($_.Exception.Message)"
}

Write-Output "DevSpace Codex shell patch applied: $TargetPath"
Write-Output "Backup: $backupPath"
