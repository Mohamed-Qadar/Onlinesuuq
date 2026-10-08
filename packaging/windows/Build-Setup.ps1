[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [string]$InnoCompiler = (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    [string]$CrtDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Run this packaging script in 64-bit PowerShell on an x64 Windows build machine.'
}
$apiUri = $null
if (-not [Uri]::TryCreate($ApiUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -ne 'https' -or -not $apiUri.AbsolutePath.EndsWith('/api/v1/') -or
    $apiUri.UserInfo -or $apiUri.Query -or $apiUri.Fragment) {
    throw 'ApiUrl must be a real HTTPS URL ending in /api/v1/, without credentials, query or fragment.'
}
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$flutter = Join-Path $root '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $flutter = $flutterCommand.Source
}
if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw 'Install Inno Setup 6.3+ or supply -InnoCompiler.' }
$pubspec = Get-Content -LiteralPath (Join-Path $root 'mobile\pubspec.yaml') -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$')
if (-not $match.Success) { throw 'Use a stable x.y.z+build version in mobile/pubspec.yaml.' }
$version = $match.Groups[1].Value
Push-Location (Join-Path $root 'mobile')
try {
    & $flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    & $flutter build windows --release "--dart-define=API_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed; no installer was generated.' }
} finally { Pop-Location }
$runtimeArgs = @{}
if ($CrtDirectory) { $runtimeArgs['CrtDirectory'] = $CrtDirectory }
& (Join-Path $PSScriptRoot 'Copy-VCRuntime.ps1') @runtimeArgs
& $InnoCompiler "/DMyAppVersion=$version" (Join-Path $PSScriptRoot 'Onlinesuuq.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
$setup = Join-Path $root 'dist\Onlinesuuq-Setup.exe'
$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$setup.sha256" -Encoding ascii -Value "$hash  Onlinesuuq-Setup.exe"
Write-Output "Installer: $setup"
Write-Output "Version: $version"
