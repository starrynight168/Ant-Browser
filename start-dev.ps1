param([string[]]$WailsArgs = @())

$repoRoot = $PSScriptRoot
$toolRoot = Join-Path $repoRoot '.tools'
$flutterRoots = @(
    (Join-Path $toolRoot 'flutter'),
    (Join-Path $repoRoot '..\.toolchains\flutter\flutter')
)
$flutterBin = $flutterRoots |
    ForEach-Object { Join-Path $_ 'bin' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ 'flutter.bat') } |
    Select-Object -First 1

$flutterCommand = if ($flutterBin) {
    Join-Path $flutterBin 'flutter.bat'
} else {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { $command.Source } else { $null }
}
if (-not $flutterCommand) {
    throw 'Flutter SDK not found. Install it under .tools\flutter, E:\app\.toolchains\flutter\flutter, or add flutter to PATH.'
}

$wailsPath = Join-Path $toolRoot 'wails.exe'
if (-not (Test-Path -LiteralPath $wailsPath -PathType Leaf)) {
    $command = Get-Command wails -ErrorAction SilentlyContinue
    if ($command) { $wailsPath = $command.Source } else { throw 'Wails CLI not found. Install Wails or place wails.exe under .tools.' }
}

$previousPath = $env:PATH
try {
    $pathEntries = @()
    $goBin = Join-Path $toolRoot 'go\bin'
    if (Test-Path -LiteralPath $goBin -PathType Container) { $pathEntries += $goBin }
    if ($flutterBin) { $pathEntries += $flutterBin }
    if ($pathEntries.Count -gt 0) { $env:PATH = ($pathEntries -join ';') + ';' + $env:PATH }

    Push-Location -LiteralPath $repoRoot
    try {
        & $wailsPath dev @WailsArgs
        if ($LASTEXITCODE -ne 0) { throw "Wails dev failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:PATH = $previousPath
}
