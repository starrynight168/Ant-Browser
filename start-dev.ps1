param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug'
)

$repoRoot = $PSScriptRoot
& (Join-Path $repoRoot 'bat\build-native.ps1') -Mode $Mode
if ($LASTEXITCODE -ne 0) { throw 'Flutter 原生桌面版构建失败。' }

$outputDirectory = Join-Path $repoRoot "build\native\$Mode"
$previousAppRoot = $env:ANT_BROWSER_APP_ROOT
$env:ANT_BROWSER_APP_ROOT = $repoRoot
Push-Location -LiteralPath $outputDirectory
try {
    & .\ant-chrome.exe
    if ($LASTEXITCODE -ne 0) { throw "Ant Browser native host exited with code $LASTEXITCODE" }
}
finally {
    Pop-Location
    $env:ANT_BROWSER_APP_ROOT = $previousAppRoot
}
