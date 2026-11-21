param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release'
)

$candidateRoots = @(
    (Join-Path $PSScriptRoot '.tools\flutter'),
    (Join-Path $PSScriptRoot '..\.toolchains\flutter\flutter')
)
$flutterCommand = $null
foreach ($root in $candidateRoots) {
    $candidate = Join-Path $root 'bin\flutter.bat'
    if (Test-Path -LiteralPath $candidate) {
        $flutterCommand = $candidate
        break
    }
}
if (-not $flutterCommand) {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { $flutterCommand = $command.Source }
}
if (-not $flutterCommand) {
    throw 'Flutter SDK not found. Install it under E:\app\.toolchains\flutter\flutter or set PATH.'
}

Push-Location -LiteralPath (Join-Path $PSScriptRoot 'frontend_flutter')
try {
    & $flutterCommand pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency setup failed.' }

    $modeArgument = if ($Mode -eq 'debug') { '--debug' } else { '--release' }
    $outputDirectory = Join-Path $PSScriptRoot 'frontend_flutter\build\web'
    & $flutterCommand build web $modeArgument --base-href / --output $outputDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
}
finally {
    Pop-Location
}
