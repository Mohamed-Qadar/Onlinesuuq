$ErrorActionPreference = 'Stop'
$install = Join-Path $env:RUNNER_TEMP 'Onlinesuuq-Install-Test'
$setup = (Resolve-Path 'dist/Onlinesuuq-Setup.exe').Path
$proc = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="' + $install + '"')) -WindowStyle Hidden -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "Setup failed: $($proc.ExitCode)" }
$exe = Join-Path $install 'Onlinesuuq.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Installed executable missing.' }
$app = Start-Process -FilePath $exe -WorkingDirectory $install -WindowStyle Hidden -PassThru
try {
    Start-Sleep -Seconds 15
    $app.Refresh()
    if ($app.HasExited) { throw 'Offline app exited unexpectedly.' }
    # Include hidden windows because CI launches without a visible window.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class InventoryWindowCheck {
    public delegate bool Callback(IntPtr hwnd, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr state);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    public static bool Exists(uint id) {
        bool found = false;
        EnumWindows((hwnd, state) => { uint pid; GetWindowThreadProcessId(hwnd, out pid); if (pid == id) found = true; return true; }, IntPtr.Zero);
        return found;
    }
}
'@
    if (-not [InventoryWindowCheck]::Exists($app.Id)) { throw 'Offline app did not create a window.' }
    $locks = @(Get-ChildItem -LiteralPath $env:APPDATA -Filter inventory.lock -Recurse -ErrorAction SilentlyContinue)
    if ($locks.Count -eq 0) { throw 'Offline inventory was not initialized.' }
    Write-Output 'Installer and native offline startup smoke check passed.'
} finally {
    if (-not $app.HasExited) {
        $null = $app.CloseMainWindow()
        if (-not $app.WaitForExit(10000)) { Stop-Process -Id $app.Id }
    }
}
$uninstaller = Join-Path $install 'unins000.exe'
$uninstall = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw 'Uninstall failed.' }
Write-Output 'Uninstall smoke check passed.'
