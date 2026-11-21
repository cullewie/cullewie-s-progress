# Sets every active display to the highest refresh rate it offers at its current resolution.
# Runs after the NVIDIA driver install, when Windows often picks 60 Hz.
param([switch]$TestOnly)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DisplayRate {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplayDevices(string lpDevice, int iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, int dwFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr lParam);
}
'@
$CDS_UPDATEREGISTRY = 0x1; $CDS_TEST = 0x2; $ENUM_CURRENT = -1; $DM_DISPLAYFREQUENCY = 0x400000
$failed = 0
# Active displays come from Windows Forms (names like \\.\DISPLAY8; numbers can have gaps).
# Typed variables: an untyped struct variable is wrapped by PowerShell and [ref] then passes a copy.
Add-Type -AssemblyName System.Windows.Forms
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
    $dev = [pscustomobject]@{ DeviceName = $screen.DeviceName }
    [DisplayRate+DEVMODE]$current = New-Object DisplayRate+DEVMODE
    $current.dmSize = [Runtime.InteropServices.Marshal]::SizeOf([type][DisplayRate+DEVMODE])
    if (-not [DisplayRate]::EnumDisplaySettings($dev.DeviceName, $ENUM_CURRENT, [ref]$current)) { continue }
    $best = 0
    [DisplayRate+DEVMODE]$mode = New-Object DisplayRate+DEVMODE
    $mode.dmSize = $current.dmSize
    for ($m = 0; [DisplayRate]::EnumDisplaySettings($dev.DeviceName, $m, [ref]$mode); $m++) {
        if ($mode.dmPelsWidth -eq $current.dmPelsWidth -and $mode.dmPelsHeight -eq $current.dmPelsHeight -and $mode.dmDisplayFrequency -gt $best) { $best = $mode.dmDisplayFrequency }
    }
    $line = '{0} {1}x{2}: {3} Hz, highest {4} Hz' -f $dev.DeviceName, $current.dmPelsWidth, $current.dmPelsHeight, $current.dmDisplayFrequency, $best
    if ($best -le $current.dmDisplayFrequency) { Write-Host "$line - already highest"; continue }
    $current.dmDisplayFrequency = $best
    $current.dmFields = $DM_DISPLAYFREQUENCY
    $flags = if ($TestOnly) { $CDS_TEST } else { $CDS_UPDATEREGISTRY }
    $result = [DisplayRate]::ChangeDisplaySettingsEx($dev.DeviceName, [ref]$current, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    if ($result -eq 0) { Write-Host "$line - set to $best Hz$(if ($TestOnly) { ' (test only)' })" -ForegroundColor Green }
    else { Write-Host "$line - Windows refused the change (code $result)" -ForegroundColor Red; $failed++ }
}
exit $failed
