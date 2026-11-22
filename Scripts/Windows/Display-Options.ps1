# Asks two display questions after the GPU driver install and applies the answers:
#   full-screen GPU scaling (stretch lower resolutions to the whole screen)
#   digital vibrance (NVIDIA) / saturation (AMD)
# -Scaling / -Level skip the questions. -TestOnly validates and reads, but changes nothing.
param(
    [ValidateSet('', 'yes', 'no')][string]$Scaling = '',
    [string]$Level = '',
    [switch]$TestOnly,
    # used by the logon task: sets the saved vibrance again, no questions, no scaling
    [switch]$Reapply
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class DisplayOptions {
    // ---------- Windows display config (works for every GPU vendor) ----------
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation;
        public uint scaling; public uint refreshNum; public uint refreshDen; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential, Size = 64)] public struct MODE_INFO { public uint infoType; public uint id; public LUID adapterId; public ulong u0, u1, u2, u3, u4, u5; }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PATH_INFO[] paths, ref uint numModes, [Out] MODE_INFO[] modes, IntPtr topology);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(uint numPaths, [In] PATH_INFO[] paths, uint numModes, [In] MODE_INFO[] modes, uint flags);

    const uint QDC_ONLY_ACTIVE_PATHS = 2;
    const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x20, SDC_VALIDATE = 0x40, SDC_APPLY = 0x80, SDC_SAVE_TO_DATABASE = 0x200, SDC_ALLOW_CHANGES = 0x400;
    public const uint SCALING_STRETCHED = 3;

    // returns the current scaling of every active display path, then (when set) switches all of them to stretched
    public static string SetStretched(bool apply) {
        uint numPaths, numModes;
        int r = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
        if (r != 0) return "GetDisplayConfigBufferSizes failed: " + r;
        PATH_INFO[] paths = new PATH_INFO[numPaths];
        MODE_INFO[] modes = new MODE_INFO[numModes];
        r = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
        if (r != 0) return "QueryDisplayConfig failed: " + r;
        List<string> before = new List<string>();
        for (int i = 0; i < numPaths; i++) {
            before.Add(paths[i].targetInfo.scaling.ToString());
            paths[i].targetInfo.scaling = SCALING_STRETCHED;
        }
        uint flags = SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | (apply ? (SDC_APPLY | SDC_SAVE_TO_DATABASE) : SDC_VALIDATE);
        r = SetDisplayConfig(numPaths, paths, numModes, modes, flags);
        return "paths=" + numPaths + " scaling before=" + string.Join(",", before.ToArray()) + " result=" + r;
    }

    // ---------- NVIDIA digital vibrance (nvapi64.dll) ----------
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr NvQuery(uint id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvInitialize();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvEnumDisplay(int index, out IntPtr handle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvGetDvc(IntPtr handle, uint outputId, ref NV_DVC_INFO info);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvSetDvc(IntPtr handle, uint outputId, int level);
    [StructLayout(LayoutKind.Sequential)] public struct NV_DVC_INFO { public uint version; public int currentLevel; public int minLevel; public int maxLevel; }

    static T Nv<T>(uint id) where T : class {
        IntPtr p = NvQuery(id);
        if (p == IntPtr.Zero) throw new Exception("NVAPI function 0x" + id.ToString("X8") + " not found");
        return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
    }

    // percent = NVIDIA Control Panel scale: 50 = default (no boost), 100 = highest; -1 only reads
    public static List<string> NvidiaVibrance(int percent, bool apply) {
        List<string> log = new List<string>();
        int r = Nv<NvInitialize>(0x0150E828)();
        if (r != 0) { log.Add("NvAPI_Initialize failed: " + r); return log; }
        NvEnumDisplay enumDisplay = Nv<NvEnumDisplay>(0x9ABDD40D);
        NvGetDvc getDvc = Nv<NvGetDvc>(0x4085DE45);
        NvSetDvc setDvc = Nv<NvSetDvc>(0x172409B4);
        for (int i = 0; i < 16; i++) {
            IntPtr h;
            if (enumDisplay(i, out h) != 0) break;
            NV_DVC_INFO info = new NV_DVC_INFO();
            info.version = (uint)(Marshal.SizeOf(typeof(NV_DVC_INFO)) | (1 << 16));
            r = getDvc(h, 0, ref info);
            if (r != 0) { log.Add("display " + i + ": NvAPI_GetDVCInfo failed: " + r); continue; }
            string line = "display " + i + ": level " + info.currentLevel + " (range " + info.minLevel + ".." + info.maxLevel + ")";
            if (percent >= 0) {
                int level = (int)Math.Round((percent - 50) / 50.0 * info.maxLevel);
                level = Math.Max(info.minLevel, Math.Min(info.maxLevel, level));
                if (apply) {
                    r = setDvc(h, 0, level);
                    line += r == 0 ? " -> " + level : " -> NvAPI_SetDVCLevel failed: " + r;
                }
                else line += " -> would set " + level;
            }
            log.Add(line);
        }
        if (log.Count == 0) log.Add("no NVIDIA display found");
        return log;
    }

    // ---------- AMD saturation and GPU scaling (atiadlxx.dll) ----------
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate IntPtr AdlAlloc(int size);
    static readonly AdlAlloc allocKeepAlive = new AdlAlloc(delegate(int size) { return Marshal.AllocCoTaskMem(size); });
    [DllImport("atiadlxx.dll")] static extern int ADL2_Main_Control_Create(AdlAlloc callback, int connectedOnly, out IntPtr context);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Main_Control_Destroy(IntPtr context);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr context, out int count);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr context, IntPtr info, int size);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Display_DisplayInfo_Get(IntPtr context, int adapter, out int count, out IntPtr info, int forceDetect);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Display_Color_Get(IntPtr context, int adapter, int display, int type, out int cur, out int def, out int min, out int max, out int step);
    [DllImport("atiadlxx.dll")] static extern int ADL2_Display_Color_Set(IntPtr context, int adapter, int display, int type, int value);
    [DllImport("atiadlxx.dll")] static extern int ADL2_DFP_GPUScalingEnable_Set(IntPtr context, int adapter, int display, int enable);

    const int ADL_DISPLAY_COLOR_SATURATION = 4;   // adl_defines.h: 1 << 2 (8 would be hue)
    const int ADAPTERINFO_SIZE = 1572, INDEX_OFFSET = 4, VENDOR_OFFSET = 4 + 4 + 256 + 12, PRESENT_OFFSET = VENDOR_OFFSET + 4 + 512;
    const int DISPLAYINFO_SIZE = 552, INFOVALUE_OFFSET = 548;

    // percent = AMD Software scale: 100 = default, 0..200; -1 leaves it. stretch: turn on GPU scaling.
    public static List<string> Amd(int percent, bool stretch, bool apply) {
        List<string> log = new List<string>();
        IntPtr ctx;
        int r = ADL2_Main_Control_Create(allocKeepAlive, 1, out ctx);
        if (r != 0) { log.Add("ADL2_Main_Control_Create failed: " + r); return log; }
        try {
            int count;
            ADL2_Adapter_NumberOfAdapters_Get(ctx, out count);
            if (count <= 0) { log.Add("no AMD adapter found"); return log; }
            IntPtr buf = Marshal.AllocCoTaskMem(ADAPTERINFO_SIZE * count);
            try {
                for (int b = 0; b < ADAPTERINFO_SIZE * count; b++) Marshal.WriteByte(buf, b, 0);
                r = ADL2_Adapter_AdapterInfo_Get(ctx, buf, ADAPTERINFO_SIZE * count);
                if (r != 0) { log.Add("ADL2_Adapter_AdapterInfo_Get failed: " + r); return log; }
                HashSet<string> done = new HashSet<string>();
                for (int a = 0; a < count; a++) {
                    IntPtr p = new IntPtr(buf.ToInt64() + (long)a * ADAPTERINFO_SIZE);
                    int index = Marshal.ReadInt32(p, INDEX_OFFSET);
                    if (Marshal.ReadInt32(p, VENDOR_OFFSET) != 0x1002 || Marshal.ReadInt32(p, PRESENT_OFFSET) == 0) continue;
                    int displays; IntPtr dinfo;
                    if (ADL2_Display_DisplayInfo_Get(ctx, index, out displays, out dinfo, 0) != 0 || dinfo == IntPtr.Zero) continue;
                    try {
                        for (int d = 0; d < displays; d++) {
                            IntPtr q = new IntPtr(dinfo.ToInt64() + (long)d * DISPLAYINFO_SIZE);
                            int logical = Marshal.ReadInt32(q, 0), owner = Marshal.ReadInt32(q, 8);
                            int value = Marshal.ReadInt32(q, INFOVALUE_OFFSET);
                            // connected (1) and mapped to a desktop (2), and owned by this adapter index
                            if ((value & 3) != 3 || owner != index || !done.Add(owner + ":" + logical)) continue;
                            string line = "adapter " + index + " display " + logical + ":";
                            int cur, def, min, max, step;
                            if (ADL2_Display_Color_Get(ctx, index, logical, ADL_DISPLAY_COLOR_SATURATION, out cur, out def, out min, out max, out step) == 0) {
                                line += " saturation " + cur + " (default " + def + ", range " + min + ".." + max + ")";
                                if (percent >= 0) {
                                    int v = Math.Max(min, Math.Min(max, percent));
                                    if (apply) { r = ADL2_Display_Color_Set(ctx, index, logical, ADL_DISPLAY_COLOR_SATURATION, v); line += r == 0 ? " -> " + v : " -> set failed: " + r; }
                                    else line += " -> would set " + v;
                                }
                            }
                            else line += " saturation not supported";
                            if (stretch) {
                                if (apply) { r = ADL2_DFP_GPUScalingEnable_Set(ctx, index, logical, 1); line += r == 0 ? ", GPU scaling on" : ", GPU scaling failed: " + r; }
                                else line += ", would turn GPU scaling on";
                            }
                            log.Add(line);
                        }
                    }
                    finally { Marshal.FreeCoTaskMem(dinfo); }
                }
            }
            finally { Marshal.FreeCoTaskMem(buf); }
        }
        finally { ADL2_Main_Control_Destroy(ctx); }
        if (log.Count == 0) log.Add("no connected AMD display found");
        return log;
    }
}
'@

$gpus = @(Get-CimInstance Win32_VideoController)
$hasNvidia = [bool]($gpus | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE&*' }) -and (Test-Path "$env:SystemRoot\System32\nvapi64.dll")
$hasAmd = [bool]($gpus | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_1002&*' }) -and (Test-Path "$env:SystemRoot\System32\atiadlxx.dll")
$failed = 0
$taskName = 'cullewie-vibrance'

if ($Reapply) {
    # the driver keeps the vibrance level only until restart; wait for the driver's own startup first
    Start-Sleep -Seconds 15
    $Scaling = 'no'
}
Write-Host 'Display options' -ForegroundColor Cyan
if (-not $Scaling) {
    $answer = Read-Host 'Tam ekran olcekleme acilsin mi? Dusuk cozunurlukler (or. 4:3) tum ekrana yayilir. (E/H)'
    $Scaling = if ($answer -match '^\s*[eEyY]') { 'yes' } else { 'no' }
}
if (-not $PSBoundParameters.ContainsKey('Level')) {
    if ($hasNvidia) { $Level = Read-Host 'Dijital canlilik yuzde kac olsun? 50 = varsayilan, 100 = en yuksek (bos = dokunma)' }
    elseif ($hasAmd) { $Level = Read-Host 'Doygunluk yuzde kac olsun? 100 = varsayilan, 200 = en yuksek, en az 100 (bos = dokunma)' }
    else { $Level = '' }
}
$percent = -1
if ("$Level".Trim()) {
    if ("$Level".Trim() -notmatch '^\d{1,3}$') { Write-Host "Not a number: $Level. Vibrance left as is." -ForegroundColor Yellow }
    else {
        $percent = [int]"$Level".Trim()
        if ($hasNvidia) { $percent = [Math]::Max(50, [Math]::Min(100, $percent)) }
        else { $percent = [Math]::Max(100, [Math]::Min(200, $percent)) }   # below 100 would wash the colours out
    }
}

if ($Scaling -eq 'yes') {
    # current displays right away, through Windows itself (NVIDIA and AMD both honour it)
    $result = [DisplayOptions]::SetStretched(-not $TestOnly)
    Write-Host "Full-screen scaling: $result$(if ($TestOnly) { ' (test only)' })"
    if ($result -notmatch 'result=0$') { $failed++ }
    # every display layout Windows has saved, so other monitors or layouts get it too
    if (-not $TestOnly) {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $null -ne (Get-ItemProperty $_.PSPath -Name Scaling -ErrorAction SilentlyContinue) } |
            ForEach-Object { try { Set-ItemProperty $_.PSPath -Name Scaling -Value 3 -Type DWord } catch { } }
    }
}
else { Write-Host 'Full-screen scaling: left as is' }

try {
    if ($hasNvidia) {
        [DisplayOptions]::NvidiaVibrance($percent, -not $TestOnly) | ForEach-Object { Write-Host "Digital vibrance: $_"; if ($_ -match 'failed') { $failed++ } }
    }
    if ($hasAmd -and ($percent -ge 0 -or $Scaling -eq 'yes')) {
        [DisplayOptions]::Amd($(if ($hasNvidia) { -1 } else { $percent }), $Scaling -eq 'yes', -not $TestOnly) | ForEach-Object { Write-Host "AMD: $_"; if ($_ -match 'failed') { $failed++ } }
    }
    if (-not $hasNvidia -and -not $hasAmd) { Write-Host 'No NVIDIA or AMD driver found. Vibrance skipped.' -ForegroundColor Yellow }
}
catch {
    Write-Host "Vibrance could not be set: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# NVIDIA forgets the level at restart (nothing is saved by the driver), so a logon task sets it again
if ($percent -ge 0 -and -not $TestOnly -and -not $Reapply -and ($hasNvidia -or $hasAmd)) {
    $isDefault = ($hasNvidia -and $percent -eq 50) -or (-not $hasNvidia -and $percent -eq 100)
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if (-not $isDefault) {
        try {
            $dir = Join-Path $env:ProgramData 'cullewie'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $copy = Join-Path $dir 'Display-Options.ps1'
            Copy-Item -LiteralPath $PSCommandPath -Destination $copy -Force
            $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$copy`" -Reapply -Level $percent"
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            Write-Host "Vibrance is set again at every sign-in (task $taskName)." -ForegroundColor Green
        }
        catch { Write-Host "Could not create the sign-in task: $($_.Exception.Message)" -ForegroundColor Red; $failed++ }
    }
}
exit $failed
