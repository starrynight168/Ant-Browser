& (Join-Path $PSScriptRoot 'build-native.ps1') -Mode release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
