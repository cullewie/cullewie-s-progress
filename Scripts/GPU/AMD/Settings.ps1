# AMD Software (Adrenalin) settings. Writes only to AMD display adapters. Ends with the highest refresh rate.
$ErrorActionPreference = 'Continue'
$classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$adapters = @(Get-ChildItem $classKey -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' -and (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProviderName -match 'Advanced Micro Devices' })
if (-not $adapters.Count) {
    Write-Host 'No AMD display driver found. Skipping AMD settings.' -ForegroundColor Yellow
    exit 0
}

function Set-Value([string]$Path, [string]$Name, $Value, [string]$Type) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Type -eq 'Binary') { $Value = [byte[]]($Value -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

Write-Host 'AMD Software settings' -ForegroundColor Cyan

# open and close AMD Software once so it creates its own keys and the settings below stick
$rs = "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe"
if (Test-Path $rs) {
    Start-Process $rs
    Start-Sleep -Seconds 30
    Stop-Process -Name RadeonSoftware -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# app: manual updates, no issue reporting, no hotkeys, tray, overlay, browser, ads, toasts or animations
Set-Value 'HKCU:\Software\AMD\CN' 'AutoUpdate' 0 DWord
Set-Value 'HKCU:\Software\AMD\AIM' 'LaunchBugTool' 0 DWord
Set-Value 'HKCU:\Software\AMD\DVR' 'HotkeysDisabled' 1 DWord
Set-Value 'HKCU:\Software\AMD\CN' 'SystemTray' 'false' String
Set-Value 'HKCU:\Software\AMD\DVR' 'ShowRSOverlay' 'false' String
Set-Value 'HKCU:\Software\AMD\CN' 'RSXBrowserUnavailable' 'true' String
Set-Value 'HKCU:\Software\AMD\CN' 'AllowWebContent' 'false' String
Set-Value 'HKCU:\Software\AMD\CN' 'CN_Hide_Toast_Notification' 'true' String
Set-Value 'HKCU:\Software\AMD\CN' 'AnimationEffect' 'false' String
Set-Value 'HKCU:\Software\AMD\CN' 'WizardProfile' 'PROFILE_CUSTOM' String
Set-Value 'HKCU:\Software\AMD\CN\CustomResolutions' 'EulaAccepted' 'true' String
Set-Value 'HKCU:\Software\AMD\CN\DisplayOverride' 'EulaAccepted' 'true' String

foreach ($a in $adapters) {
    # Radeon Anti-Lag on; tuning pages unlocked (no overclock is applied)
    Set-Value $a.PSPath 'KMD_DeLagEnabled' 1 DWord
    Set-Value $a.PSPath 'IsAutoDefault' '00000000' Binary
    Set-Value $a.PSPath 'IsComponentControl' '0f000000' Binary
    foreach ($umd in Get-ChildItem $a.PSPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'UMD' }) {
        Set-Value $umd.PSPath 'VSyncControl' '3000' Binary          # wait for vertical refresh: always off
        Set-Value $umd.PSPath 'TFQ' '3200' Binary                   # texture filtering quality: performance
        Set-Value $umd.PSPath 'Tessellation' '3100' Binary          # tessellation level: off
        Set-Value $umd.PSPath 'Tessellation_OPTION' '3200' Binary   # tessellation mode: override application
    }
    foreach ($pw in Get-ChildItem $a.PSPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'power_v1' }) {
        Set-Value $pw.PSPath 'abmlevel' '00000000' Binary           # Vari-Bright off: full brightness
    }
    Write-Host "  $($a.PSChildName): $((Get-ItemProperty $a.PSPath).DriverDesc)"
}

# notifications already shown
Remove-Item 'HKCU:\Software\AMD\CN\Notification' -Recurse -Force -ErrorAction SilentlyContinue
New-Item 'HKCU:\Software\AMD\CN\Notification' -Force | Out-Null
foreach ($k in 'FreeSync', 'OverlayNotification', 'VirtualSuperResolution') { Set-Value "HKCU:\Software\AMD\CN\$k" 'AlreadyNotified' 1 DWord }

# highest refresh rate: a fresh driver often starts the display at 60 Hz (same script NVIDIA Settings runs)
$refreshRate = Join-Path $PSScriptRoot '..\Refresh-Rate.ps1'
if (Test-Path $refreshRate) {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $refreshRate | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "Refresh rate: $LASTEXITCODE display(s) could not be changed, see above." -ForegroundColor Yellow }
}
else { Write-Host "Refresh rate: skipped, $refreshRate not found." -ForegroundColor Yellow }

Write-Host 'AMD settings applied.' -ForegroundColor Green
exit 0
