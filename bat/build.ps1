Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterRoots = @(
    (Join-Path $repoRoot ".tools\flutter"),
    (Join-Path $repoRoot "..\.toolchains\flutter\flutter")
)
$flutterBin = $flutterRoots |
    ForEach-Object { Join-Path $_ "bin" } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ "flutter.bat") } |
    Select-Object -First 1
$oldPath = $env:PATH
$wailsPath = Join-Path $repoRoot ".tools\wails.exe"

try {
    Set-Location $repoRoot
    $pathEntries = @((Join-Path $repoRoot ".tools\go\bin"))
    if ($flutterBin) { $pathEntries += $flutterBin }
    $env:PATH = ($pathEntries -join ";") + ";" + $oldPath

    if (-not (Test-Path -LiteralPath $wailsPath)) {
        $wailsCommand = Get-Command wails -ErrorAction Stop
        $wailsPath = $wailsCommand.Source
    }

    & $wailsPath build -tags native_webview2loader
    if ($LASTEXITCODE -ne 0) { throw "Wails build failed with exit code $LASTEXITCODE" }

    $binDir = Join-Path $repoRoot "bin"
    $targetDir = Join-Path $repoRoot "build/bin/bin"
    if (Test-Path -LiteralPath $binDir -PathType Container) {
        Copy-Item -LiteralPath $binDir -Destination $targetDir -Recurse -Force
    }

    Write-Host "Build completed: build\bin\ant-chrome.exe"
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)"
    exit 1
}
finally {
    $env:PATH = $oldPath
}
