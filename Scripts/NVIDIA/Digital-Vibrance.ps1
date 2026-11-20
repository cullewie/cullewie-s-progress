
# NVIDIA DISPLAY UTILITY
# PowerShell 5.1+
# Run as Administrator

# ---------------- ADMINISTRATOR CHECK ----------------

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Start-Process PowerShell.exe -ArgumentList (
        '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    ) -Verb RunAs
    exit
}

# ---------------- CONSOLE ----------------

$Host.UI.RawUI.WindowTitle = "NVIDIA Display Utility (Administrator)"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.PrivateData.ProgressBackgroundColor = "Black"
$Host.PrivateData.ProgressForegroundColor = "White"

Clear-Host

# ---------------- NVIDIA NVAPI ----------------

$cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class NvVibranceDisplayUtility
{
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface",
        CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr QueryInterface(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int InitD();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int EnumD(uint index, out IntPtr handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int DvcD(IntPtr handle, uint outputId, IntPtr info);

    static T Get<T>(uint id) where T : class
    {
        IntPtr p = QueryInterface(id);

        if (p == IntPtr.Zero)
            throw new Exception(
                "NvAPI function 0x" + id.ToString("X") + " not available"
            );

        return (T)(object)Marshal.GetDelegateForFunctionPointer(
            p, typeof(T)
        );
    }

    // Read NVIDIA driver-reported default values.
    public static int[] GetDefaults()
    {
        InitD init = Get<InitD>(0x0150E828);

        int status = init();

        if (status != 0)
            throw new Exception(
                "NvAPI initialize failed (status " + status + ")"
            );

        EnumD en = Get<EnumD>(0x9ABDD40D);
        DvcD get = Get<DvcD>(0x0E45002D);

        List<int> defaults = new List<int>();

        for (uint i = 0; i < 16; i++)
        {
            IntPtr handle;

            if (en(i, out handle) != 0)
                break;

            IntPtr buf = Marshal.AllocHGlobal(20);

            try
            {
                for (int k = 0; k < 20; k += 4)
                    Marshal.WriteInt32(buf, k, 0);

                Marshal.WriteInt32(buf, 0, 20 | 0x10000);

                status = get(handle, 0, buf);

                if (status == 0)
                    defaults.Add(Marshal.ReadInt32(buf, 16));
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        return defaults.ToArray();
    }

    // Apply a custom Digital Vibrance value from 0 to 100.
    public static string Apply(int percent)
    {
        StringBuilder log = new StringBuilder();

        if (percent < 0 || percent > 100)
            return "Digital Vibrance must be between 0 and 100.";

        InitD init = Get<InitD>(0x0150E828);

        int status = init();

        if (status != 0)
            return "NvAPI initialize failed (status " + status + ")";

        EnumD en = Get<EnumD>(0x9ABDD40D);
        DvcD get = Get<DvcD>(0x0E45002D);
        DvcD set = Get<DvcD>(0x4A82C2B1);

        int done = 0;

        for (uint i = 0; i < 16; i++)
        {
            IntPtr handle;

            if (en(i, out handle) != 0)
                break;

            IntPtr buf = Marshal.AllocHGlobal(20);

            try
            {
                for (int k = 0; k < 20; k += 4)
                    Marshal.WriteInt32(buf, k, 0);

                Marshal.WriteInt32(buf, 0, 20 | 0x10000);

                status = get(handle, 0, buf);

                if (status != 0)
                {
                    log.AppendLine(
                        "Display " + i +
                        ": read failed (status " + status + ")"
                    );
                    continue;
                }

                int min = Marshal.ReadInt32(buf, 8);
                int max = Marshal.ReadInt32(buf, 12);
                int def = Marshal.ReadInt32(buf, 16);

                int level = percent;

                if (level < min) level = min;
                if (level > max) level = max;

                Marshal.WriteInt32(buf, 4, level);

                status = set(handle, 0, buf);

                if (status != 0)
                {
                    log.AppendLine(
                        "Display " + i +
                        ": set failed (status " + status + ")"
                    );
                }
                else
                {
                    log.AppendLine(
                        "Display " + i +
                        ": vibrance " + level +
                        " (range " + min + "-" + max +
                        ", default " + def + ")"
                    );

                    done++;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        if (done == 0)
            log.AppendLine("No display was changed.");

        return log.ToString();
    }
}
'@

# ---------------- LOAD NVAPI CLASS ----------------

if (-not ("NvVibranceDisplayUtility" -as [type])) {
    Add-Type -TypeDefinition $cs -ErrorAction Stop
}

# ---------------- SCREEN SCALING ----------------

Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host "                 SCREEN SCALING" -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Full Screen scaling mode selected." -ForegroundColor White
Write-Host "Informational only. No Windows scaling settings changed." -ForegroundColor DarkGray

# ---------------- DIGITAL VIBRANCE ----------------

Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host "                DIGITAL VIBRANCE" -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host ""

# Read actual driver defaults for warning messages.

$defaults = @()

try {
    $defaults = @(
        [NvVibranceDisplayUtility]::GetDefaults()
    )

    $uniqueDefaults = @(
        $defaults | Sort-Object -Unique
    )

    if ($uniqueDefaults.Count -eq 1) {
        $defaultText = [string]$uniqueDefaults[0]
    }
    elseif ($uniqueDefaults.Count -gt 1) {
        $defaultText = (
            $uniqueDefaults -join ", "
        ) + " (display-dependent)"
    }
    else {
        $defaultText = "Unavailable"
    }
}
catch {
    $defaultText = "Unavailable"
}

# ---------------- INPUT ----------------

Write-Host "Enter       : Apply 50" -ForegroundColor Gray
Write-Host "0 - 100     : Custom Digital Vibrance" -ForegroundColor Gray
Write-Host ""

$applyValue = $null
$confirmed = $false

while (-not $confirmed) {

    $inputValue = Read-Host "Digital Vibrance"

    $parsedValue = 0

    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        $parsedValue = 50
    }
    elseif (
        -not [int]::TryParse(
            $inputValue.Trim(),
            [ref]$parsedValue
        ) -or
        $parsedValue -lt 0 -or
        $parsedValue -gt 100
    ) {
        Write-Host ""
        Write-Host "Invalid input. Enter a value between 0 and 100." -ForegroundColor Yellow
        Write-Host ""
        continue
    }

    # ---------------- BELOW 50 WARNING ----------------

    if ($parsedValue -lt 50) {

        Write-Host ""
        Write-Host "--------------------------------------------------" -ForegroundColor Yellow
        Write-Host "                 LOW VALUE WARNING" -ForegroundColor Yellow
        Write-Host "--------------------------------------------------" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "Selected Digital Vibrance : $parsedValue" -ForegroundColor White
        Write-Host "Reference level           : 50" -ForegroundColor White
        Write-Host "Driver-reported default   : $defaultText" -ForegroundColor Cyan

        Write-Host ""
        Write-Host "You are about to apply a value below 50." -ForegroundColor Yellow
        Write-Host "This will result in lower color vibrance." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Do you want to continue?" -ForegroundColor White
        Write-Host ""

        $answer = Read-Host "[Y] Yes / [N] No"

        if ($answer.Trim().ToUpperInvariant() -in @("Y", "YES")) {
            $applyValue = $parsedValue
            $confirmed = $true
        }
        elseif ($answer.Trim().ToUpperInvariant() -in @("N", "NO")) {
            Write-Host ""
            Write-Host "Selection cancelled. Enter another value." -ForegroundColor Yellow
            Write-Host ""
        }
        else {
            Write-Host ""
            Write-Host "Invalid confirmation. Please enter Y or N." -ForegroundColor Yellow
            Write-Host ""
        }
    }
    else {
        $applyValue = $parsedValue
        $confirmed = $true
    }
}

# ---------------- APPLY ----------------

Write-Host ""
Write-Host "--------------------------------------------------" -ForegroundColor DarkGray

try {

    Write-Host "Applying Digital Vibrance: $applyValue" -ForegroundColor Cyan

    Write-Host ""

    $result = [NvVibranceDisplayUtility]::Apply($applyValue)

    Write-Host $result

}
catch {
    Write-Host ""
    Write-Host "NVAPI ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# ---------------- FINISH ----------------

Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host "                    COMPLETED" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host ""

Pause

