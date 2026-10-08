# Copy the licensed, redistributable x64 CRT from the build toolchain.
# Do not obtain DLLs from third-party download sites or copy from System32.
[CmdletBinding()]
param(
    [string]$ReleaseDir = (Join-Path $PSScriptRoot '..\..\mobile\build\windows\x64\runner\Release'),
    [string]$CrtDirectory
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir 'Onlinesuuq.exe'))) {
    throw 'Build the Windows x64 release first: Onlinesuuq.exe was not found.'
}
$target = (Resolve-Path -LiteralPath $ReleaseDir).Path
if (-not $CrtDirectory) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio with Desktop development with C++ is required.' }
    $vsInstall = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vsInstall) { throw 'Visual C++ build tools were not found.' }
    $redist = Join-Path ($vsInstall | Select-Object -First 1) 'VC\Redist\MSVC'
    $versions = Get-ChildItem -LiteralPath $redist -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($versionDir in $versions) {
        $x64 = Join-Path $versionDir.FullName 'x64'
        if (-not (Test-Path -LiteralPath $x64)) { continue }
        $crt = Get-ChildItem -LiteralPath $x64 -Directory |
            Where-Object { $_.Name -match '^Microsoft\.VC\d+\.CRT$' } |
            Select-Object -First 1
        if ($crt) { $CrtDirectory = $crt.FullName; break }
    }
}
if (-not $CrtDirectory) { throw 'x64 redistributable CRT not found. Supply -CrtDirectory from your build toolchain.' }
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $CrtDirectory $name))) { throw "Missing required runtime: $name" }
}
Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll' -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target -Force }
Write-Output "x64 VC++ runtime copied to $target"
