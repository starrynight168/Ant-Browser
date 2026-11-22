param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release'
)

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

$pubspecPath = Join-Path $repoRoot 'frontend_flutter\pubspec.yaml'
$versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*(\d+\.\d+\.\d+)' | Select-Object -First 1
if (-not $versionLine) { throw '无法从 Flutter pubspec.yaml 读取应用版本。' }
$appVersion = $versionLine.Matches[0].Groups[1].Value

Push-Location (Join-Path $repoRoot 'frontend_flutter')
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 依赖准备失败。' }

    & $flutter build windows "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows 构建失败。' }
}
finally {
    Pop-Location
}

$configuration = $Mode.Substring(0, 1).ToUpperInvariant() + $Mode.Substring(1)
$releaseDirectory = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'frontend_flutter\build\windows') -Directory |
    ForEach-Object { Join-Path $_.FullName "runner\$configuration" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $releaseDirectory) { throw '找不到 Flutter Windows Release 输出目录。' }

$outputDirectory = Join-Path $repoRoot "build\native\$Mode"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $releaseDirectory '*') -Destination $outputDirectory -Recurse -Force

Push-Location $repoRoot
$previousPath = $env:PATH
$previousGoPath = $env:GOPATH
try {
    $goToolRoot = Join-Path $env:TEMP 'ant-browser-go-1.22.12-codex'
    $goToolBin = Join-Path $goToolRoot 'go\bin'
    if (Test-Path -LiteralPath $goToolBin -PathType Container) {
        $env:GOPATH = Join-Path $goToolRoot 'gopath'
        $env:PATH = $goToolBin + ';' + $env:PATH
    }
    $linkerFlags = "-X main.appVersion=$appVersion"
    if ($Mode -eq 'release') { $linkerFlags = "-H=windowsgui $linkerFlags" }
    & $go build -ldflags $linkerFlags -o (Join-Path $outputDirectory 'ant-chrome.exe') ./cmd/nativehost
    if ($LASTEXITCODE -ne 0) { throw 'Go 桌面宿主构建失败。' }
}
finally {
    Pop-Location
    $env:PATH = $previousPath
    $env:GOPATH = $previousGoPath
}

$resourceDirectory = Join-Path $repoRoot 'bin'
if (Test-Path -LiteralPath $resourceDirectory -PathType Container) {
    Copy-Item -LiteralPath $resourceDirectory -Destination $outputDirectory -Recurse -Force
}

Write-Host "原生 Flutter $Mode 版本已构建：$outputDirectory"
