Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutterCandidates = @(
    (Join-Path $repoRoot '.tools\flutter\bin\flutter.bat'),
    (Join-Path $repoRoot '..\.toolchains\flutter\flutter\bin\flutter.bat')
)
$goCandidates = @(
    (Join-Path $repoRoot '.tools\go\bin\go.exe'),
    (Join-Path $repoRoot '..\Ant-Browser-master\.tools\go\bin\go.exe')
)

$flutter = $flutterCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $flutter) {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { $flutter = $command.Source }
}
if (-not $flutter) { throw '找不到 Flutter SDK。' }

$go = $goCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $go) {
    $command = Get-Command go -ErrorAction SilentlyContinue
    if ($command) { $go = $command.Source }
}
if (-not $go) { throw '找不到 Go SDK。' }

Push-Location (Join-Path $repoRoot 'frontend_flutter')
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 依赖准备失败。' }

    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows 构建失败。' }
}
finally {
    Pop-Location
}

$releaseDirectory = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'frontend_flutter\build\windows') -Directory |
    ForEach-Object { Join-Path $_.FullName 'runner\Release' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $releaseDirectory) { throw '找不到 Flutter Windows Release 输出目录。' }

$outputDirectory = Join-Path $repoRoot 'build\native'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $releaseDirectory '*') -Destination $outputDirectory -Recurse -Force

Push-Location $repoRoot
try {
    & $go build -o (Join-Path $outputDirectory 'ant-chrome.exe') ./cmd/nativehost
    if ($LASTEXITCODE -ne 0) { throw 'Go 桌面宿主构建失败。' }
}
finally {
    Pop-Location
}

$resourceDirectory = Join-Path $repoRoot 'bin'
if (Test-Path -LiteralPath $resourceDirectory -PathType Container) {
    Copy-Item -LiteralPath $resourceDirectory -Destination $outputDirectory -Recurse -Force
}

Write-Host "原生 Flutter 版本已构建：$outputDirectory"
