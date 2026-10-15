# ============================================================
#  Clean-GhostDevices.ps1
#  Removes phantom (disconnected/ghost) USB devices:
#    - Ghost COM ports   (USB Serial Port, USB 串行设备, FTDI, CH340...)
#    - Ghost audio devices (iLoud Micro Monitor, USB audio...)
#    - Ghost USB drives / phones / hubs
#  SAFE: only devices that are NOT currently plugged in are touched.
#  Present/active devices are NEVER removed.
#
#  Usage:
#    Scan only :  powershell -ExecutionPolicy Bypass -File .\Clean-GhostDevices.ps1
#    Clean     :  powershell -ExecutionPolicy Bypass -File .\Clean-GhostDevices.ps1 -Clean
#
#  Requires: Windows 10 2004+ (pnputil /remove-device), Admin rights for cleaning.
# ============================================================
param([switch]$Clean)

$ErrorActionPreference = 'SilentlyContinue'

# ---- 1. Admin check (only needed for cleaning) ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- 2. Collect phantom devices (not present) ----
# Only USB-bus family devices. System/software devices (RAS, remote desktop,
# virtual DVD, VHD, volume snapshots...) are intentionally NEVER touched.
$includePrefixes = @('USB\', 'FTDIBUS\', 'SWD\MMDEVAPI\')

$phantom = Get-PnpDevice | Where-Object { -not $_.Present }
$targets = $phantom | Where-Object {
    $id = $_.InstanceId
    foreach ($p in $includePrefixes) {
        if ($id.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

Write-Host ""
Write-Host "=== Ghost device scan (disconnected devices only) ===" -ForegroundColor Cyan
Write-Host ("Total phantom devices on system : {0}" -f $phantom.Count)
Write-Host ("Cleanable USB-family ghosts     : {0}" -f $targets.Count)
Write-Host ""
$targets | Group-Object Class | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0,5}  x  {1}" -f $_.Count, $_.Name)
}
Write-Host ""
Write-Host "--- Detail ---"
$targets | Sort-Object Class, FriendlyName | ForEach-Object {
    Write-Host ("  [{0}] {1}" -f $_.Class, $_.FriendlyName)
}

if (-not $Clean) {
    Write-Host ""
    Write-Host "SCAN ONLY. Run with -Clean to remove them." -ForegroundColor Yellow
    exit 0
}

# ---- 3. Confirm ----
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "ERROR: Administrator rights required. Right-click -> Run as administrator." -ForegroundColor Red
    exit 1
}

Write-Host ""
$answer = Read-Host ("Remove the {0} ghost devices listed above? (Y/N)" -f $targets.Count)
if ($answer -notmatch '^[Yy]') {
    Write-Host "Cancelled. Nothing was removed." -ForegroundColor Yellow
    exit 0
}

# ---- 4. Remove ----
# Fast engine: SetupAPI in-process removal (SetupDiCallClassInstaller / DIF_REMOVE).
# ~50-100x faster than spawning pnputil once per device. Fallback: pnputil.
$useFast = $true
try {
    $src = @'
using System;
using System.Runtime.InteropServices;
public static class DevClean {
    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVINFO_DATA {
        public int cbSize;
        public Guid ClassGuid;
        public int DevInst;
        public IntPtr Reserved;
    }
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr ClassGuid, IntPtr hwndParent);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiOpenDeviceInfo(IntPtr DeviceInfoSet, string DeviceInstanceId, IntPtr hwndParent, int OpenFlags, ref SP_DEVINFO_DATA DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiCallClassInstaller(uint InstallFunction, IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData);
    [DllImport("setupapi.dll")]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    // Returns 0 on success, otherwise the Win32 error code
    public static int Remove(string instanceId) {
        IntPtr set = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
        if (set == IntPtr.Zero || set == (IntPtr)(-1)) return Marshal.GetLastWin32Error();
        try {
            SP_DEVINFO_DATA d = new SP_DEVINFO_DATA();
            d.cbSize = Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
            if (!SetupDiOpenDeviceInfo(set, instanceId, IntPtr.Zero, 0, ref d)) return Marshal.GetLastWin32Error();
            if (SetupDiCallClassInstaller(0x12 /* DIF_REMOVE */, set, ref d)) return 0;
            return Marshal.GetLastWin32Error();
        } finally {
            SetupDiDestroyDeviceInfoList(set);
        }
    }
}
'@
    Add-Type -TypeDefinition $src -ErrorAction Stop
} catch {
    Write-Host "Fast engine unavailable, falling back to pnputil (slow)." -ForegroundColor Yellow
    $useFast = $false
}

$okCount = 0
$failCount = 0
$fallbackCount = 0
$total = $targets.Count
$i = 0
foreach ($dev in $targets) {
    $i++
    $ok = $false
    $errText = ''
    if ($useFast) {
        $rc = [DevClean]::Remove($dev.InstanceId)
        if ($rc -eq 0) {
            $ok = $true
        } else {
            $errText = (New-Object System.ComponentModel.Win32Exception($rc)).Message
            # Fast engine failed on this device -> retry once with pnputil (proven to work)
            $null = pnputil /remove-device "$($dev.InstanceId)" 2>&1
            if ($LASTEXITCODE -eq 0) { $ok = $true; $fallbackCount++ }
        }
    } else {
        $null = pnputil /remove-device "$($dev.InstanceId)" 2>&1
        $ok = ($LASTEXITCODE -eq 0)
    }
    if ($ok) { $okCount++ } else { $failCount++ }
    if ($ok) {
        if (($i % 50 -eq 0) -or ($i -eq $total)) {
            Write-Host ("  [{0}/{1}] removed... (fast:{2} fallback:{3} failed:{4})" -f $i, $total, ($okCount - $fallbackCount), $fallbackCount, $failCount)
        }
    } else {
        Write-Host ("  [{0}/{1}] FAILED: {2}  ({3})  [{4}]" -f $i, $total, $dev.FriendlyName, $dev.InstanceId, $errText) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ("Removed (fast API) : {0}" -f ($okCount - $fallbackCount))
Write-Host ("Removed (pnputil)  : {0}" -f $fallbackCount)
Write-Host ("Failed             : {0}" -f $failCount)
if ($failCount -gt 0) {
    Write-Host "Note: SWD\MMDEVAPI (audio endpoint) ghosts may resist removal;"
    Write-Host "they are harmless leftovers. A reboot usually clears them." -ForegroundColor Yellow
}
Write-Host "Replug a device and it gets a fresh low COM number again."
Write-Host ""
