[CmdletBinding()]
param(
    [switch]$GuidedNvidia,
    # Full setup: download and configure DDU only; the safe-mode step runs the cleanup.
    [switch]$PrepareOnly
)

# SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host
        New-Item -ItemType Directory -Path "$env:ProgramData\Cullewie\Work" -Force | Out-Null

        # SCRIPT SILENT
        $progresspreference = 'silentlycontinue'

        Write-Host "1. DDU: Auto"
        Write-Host "2. DDU: Manual`n"
        while ($true) {
        $choice = if ($GuidedNvidia -or $PrepareOnly) { '1' } else { Read-Host " " }
        if ($choice -match '^[1-2]$') {
        switch ($choice) {
        1 {

        Clear-Host

# 7-Zip only to extract DDU: installed when missing and removed again right after; a 7-Zip the user had stays as it is
$had7z = Test-Path "$env:SystemDrive\Program Files\7-Zip\7z.exe"
if (-not $had7z) {
    IWR "https://github.com/cullewie/cullewie-s-progress/releases/download/files/7zip.exe" -OutFile "$env:ProgramData\Cullewie\Work\7zip.exe"
    if ((Get-FileHash "$env:ProgramData\Cullewie\Work\7zip.exe" -Algorithm SHA256).Hash -ne '0859c524b8a63551848f0c246abddcb1d0b7b656b0fbfe879f8d85e61a9e6edd') { throw '7zip.exe SHA-256 mismatch; download stopped.' }
    Start-Process -Wait "$env:ProgramData\Cullewie\Work\7zip.exe" -ArgumentList "/S"
    if (-not (Test-Path "$env:SystemDrive\Program Files\7-Zip\7z.exe")) { throw '7-Zip did not install; DDU cannot be extracted.' }
}

# download ddu
IWR "https://github.com/cullewie/cullewie-s-progress/releases/download/files/ddu.exe" -OutFile "$env:ProgramData\Cullewie\Work\ddu.exe"
if ((Get-FileHash "$env:ProgramData\Cullewie\Work\ddu.exe" -Algorithm SHA256).Hash -ne '9b2611ec6d5a9d8853936cc071cc4026c6cfe91beed956cd41cc81c0930acd47') { throw 'ddu.exe SHA-256 mismatch; download stopped.' }

# extract ddu with 7zip
# fresh folder: a DDU left from an earlier run must not pass the checks below, and 7z cannot overwrite the read-only Settings.xml
Remove-Item "$env:ProgramData\Cullewie\Work\ddu" -Recurse -Force -ErrorAction SilentlyContinue
& "$env:SystemDrive\Program Files\7-Zip\7z.exe" x "$env:ProgramData\Cullewie\Work\ddu.exe" -o"$env:ProgramData\Cullewie\Work\ddu" -y | Out-Null
$extractCode = $LASTEXITCODE
# the 7-Zip installed above is not needed any more
if (-not $had7z) { Start-Process -Wait "$env:SystemDrive\Program Files\7-Zip\Uninstall.exe" -ArgumentList '/S' -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\Cullewie\Work\7zip.exe" -Force -ErrorAction SilentlyContinue }
if ($extractCode -ne 0) { throw "Extracting DDU failed (7-Zip exit code $extractCode)." }

# set config for ddu
$DduConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<DisplayDriverUninstaller Version="18.1.4.2">
	<Settings>
		<SelectedLanguage>en-US</SelectedLanguage>
		<RemoveMonitors>True</RemoveMonitors>
		<RemoveCrimsonCache>True</RemoveCrimsonCache>
		<RemoveAMDDirs>True</RemoveAMDDirs>
		<RemoveAudioBus>True</RemoveAudioBus>
		<RemoveAMDKMPFD>True</RemoveAMDKMPFD>
		<RemoveNvidiaDirs>True</RemoveNvidiaDirs>
		<RemovePhysX>True</RemovePhysX>
		<Remove3DTVPlay>True</Remove3DTVPlay>
		<RemoveGFE>True</RemoveGFE>
		<RemoveNVBROADCAST>True</RemoveNVBROADCAST>
		<RemoveNVCP>True</RemoveNVCP>
		<RemoveINTELCP>True</RemoveINTELCP>
		<RemoveINTELIGS>True</RemoveINTELIGS>
		<RemoveOneAPI>True</RemoveOneAPI>
		<RemoveEnduranceGaming>True</RemoveEnduranceGaming>
		<RemoveIntelNpu>True</RemoveIntelNpu>
		<RemoveAMDCP>True</RemoveAMDCP>
		<UseRoamingConfig>False</UseRoamingConfig>
		<CheckUpdates>False</CheckUpdates>
		<CreateRestorePoint>False</CreateRestorePoint>
		<SaveLogs>False</SaveLogs>
		<RemoveVulkan>True</RemoveVulkan>
		<ShowOffer>False</ShowOffer>
		<EnableSafeModeDialog>False</EnableSafeModeDialog>
		<PreventWinUpdate>True</PreventWinUpdate>
		<UsedBCD>False</UsedBCD>
		<KeepNVCPopt>False</KeepNVCPopt>
		<RememberLastChoice>False</RememberLastChoice>
		<LastSelectedGPUIndex>0</LastSelectedGPUIndex>
		<LastSelectedTypeIndex>0</LastSelectedTypeIndex>
	</Settings>
</DisplayDriverUninstaller>
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\ddu\Settings\Settings.xml" -Value $DduConfig -Force

# set ddu config to read only
Set-ItemProperty -Path "$env:ProgramData\Cullewie\Work\ddu\Settings\Settings.xml" -Name IsReadOnly -Value $true

if ($PrepareOnly) {
    if (-not (Test-Path -LiteralPath "$env:ProgramData\Cullewie\Work\ddu\Display Driver Uninstaller.exe" -PathType Leaf)) {
        throw 'The DDU executable was not extracted successfully.'
    }
    Write-Host 'DDU is ready for the safe-mode cleanup.' -ForegroundColor Green
    exit
}

# The guided NVIDIA path cleans only NVIDIA in normal Windows mode.
if ($GuidedNvidia) {
    $dduExe = "$env:ProgramData\Cullewie\Work\ddu\Display Driver Uninstaller.exe"
    if (-not (Test-Path -LiteralPath $dduExe -PathType Leaf)) {
        throw 'The DDU executable was not extracted successfully.'
    }
    Write-Host 'Cleaning NVIDIA driver components. Safe Mode, restart, and restore point creation are disabled.' -ForegroundColor Yellow
    $cleanup = Start-Process -FilePath $dduExe -ArgumentList '-Silent -NoSafeModeMsg -NoRestorePoint -CleanNvidia -RemovePhysx -RemoveGFE -RemoveNVBROADCAST -RemoveNVCP -RemoveVulkan -RemoveNvidiaDirs -Remove3DTVPlay' -Wait -PassThru
    if ($cleanup.ExitCode -ne 0) {
        throw "DDU failed with exit code $($cleanup.ExitCode)."
    }
    Write-Host 'DDU cleanup finished. Continuing without restarting.' -ForegroundColor Green
    exit
}
# prevent downloads of drivers from windows update
cmd /c "reg add `"HKLM\Software\Microsoft\Windows\CurrentVersion\DriverSearching`" /v `"SearchOrderConfig`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# create ddu ps1 file
$DDU = @'
# SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host

# remove safe mode boot
cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"

Write-Host "DDU & RESTARTING`n" -ForegroundColor Red

# uninstall soundblaster realtek intel amd nvidia drivers & restart
Start-Process "$env:ProgramData\Cullewie\Work\ddu\Display Driver Uninstaller.exe" -ArgumentList "-CleanSoundBlaster -CleanRealtek -CleanAllGpus -Restart" -Wait
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\ddu.ps1" -Value $DDU -Force

# install runonce ddu ps1 file to run in safe boot
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*ddu`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:ProgramData\Cullewie\Work\ddu.ps1`" /f >nul 2>&1"

# turn on safe boot
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"

Write-Host "RESTARTING`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00

exit

          }
        2 {

        Clear-Host

# 7-Zip only to extract DDU: installed when missing and removed again right after; a 7-Zip the user had stays as it is
$had7z = Test-Path "$env:SystemDrive\Program Files\7-Zip\7z.exe"
if (-not $had7z) {
    IWR "https://github.com/cullewie/cullewie-s-progress/releases/download/files/7zip.exe" -OutFile "$env:ProgramData\Cullewie\Work\7zip.exe"
    if ((Get-FileHash "$env:ProgramData\Cullewie\Work\7zip.exe" -Algorithm SHA256).Hash -ne '0859c524b8a63551848f0c246abddcb1d0b7b656b0fbfe879f8d85e61a9e6edd') { throw '7zip.exe SHA-256 mismatch; download stopped.' }
    Start-Process -Wait "$env:ProgramData\Cullewie\Work\7zip.exe" -ArgumentList "/S"
    if (-not (Test-Path "$env:SystemDrive\Program Files\7-Zip\7z.exe")) { throw '7-Zip did not install; DDU cannot be extracted.' }
}

# download ddu
IWR "https://github.com/cullewie/cullewie-s-progress/releases/download/files/ddu.exe" -OutFile "$env:ProgramData\Cullewie\Work\ddu.exe"
if ((Get-FileHash "$env:ProgramData\Cullewie\Work\ddu.exe" -Algorithm SHA256).Hash -ne '9b2611ec6d5a9d8853936cc071cc4026c6cfe91beed956cd41cc81c0930acd47') { throw 'ddu.exe SHA-256 mismatch; download stopped.' }

# extract ddu with 7zip
# fresh folder: a DDU left from an earlier run must not pass the checks below, and 7z cannot overwrite the read-only Settings.xml
Remove-Item "$env:ProgramData\Cullewie\Work\ddu" -Recurse -Force -ErrorAction SilentlyContinue
& "$env:SystemDrive\Program Files\7-Zip\7z.exe" x "$env:ProgramData\Cullewie\Work\ddu.exe" -o"$env:ProgramData\Cullewie\Work\ddu" -y | Out-Null
$extractCode = $LASTEXITCODE
# the 7-Zip installed above is not needed any more
if (-not $had7z) { Start-Process -Wait "$env:SystemDrive\Program Files\7-Zip\Uninstall.exe" -ArgumentList '/S' -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\Cullewie\Work\7zip.exe" -Force -ErrorAction SilentlyContinue }
if ($extractCode -ne 0) { throw "Extracting DDU failed (7-Zip exit code $extractCode)." }

# set config for ddu
$DduConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<DisplayDriverUninstaller Version="18.1.4.2">
	<Settings>
		<SelectedLanguage>en-US</SelectedLanguage>
		<RemoveMonitors>True</RemoveMonitors>
		<RemoveCrimsonCache>True</RemoveCrimsonCache>
		<RemoveAMDDirs>True</RemoveAMDDirs>
		<RemoveAudioBus>True</RemoveAudioBus>
		<RemoveAMDKMPFD>True</RemoveAMDKMPFD>
		<RemoveNvidiaDirs>True</RemoveNvidiaDirs>
		<RemovePhysX>True</RemovePhysX>
		<Remove3DTVPlay>True</Remove3DTVPlay>
		<RemoveGFE>True</RemoveGFE>
		<RemoveNVBROADCAST>True</RemoveNVBROADCAST>
		<RemoveNVCP>True</RemoveNVCP>
		<RemoveINTELCP>True</RemoveINTELCP>
		<RemoveINTELIGS>True</RemoveINTELIGS>
		<RemoveOneAPI>True</RemoveOneAPI>
		<RemoveEnduranceGaming>True</RemoveEnduranceGaming>
		<RemoveIntelNpu>True</RemoveIntelNpu>
		<RemoveAMDCP>True</RemoveAMDCP>
		<UseRoamingConfig>False</UseRoamingConfig>
		<CheckUpdates>False</CheckUpdates>
		<CreateRestorePoint>False</CreateRestorePoint>
		<SaveLogs>False</SaveLogs>
		<RemoveVulkan>True</RemoveVulkan>
		<ShowOffer>False</ShowOffer>
		<EnableSafeModeDialog>False</EnableSafeModeDialog>
		<PreventWinUpdate>True</PreventWinUpdate>
		<UsedBCD>False</UsedBCD>
		<KeepNVCPopt>False</KeepNVCPopt>
		<RememberLastChoice>False</RememberLastChoice>
		<LastSelectedGPUIndex>0</LastSelectedGPUIndex>
		<LastSelectedTypeIndex>0</LastSelectedTypeIndex>
	</Settings>
</DisplayDriverUninstaller>
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\ddu\Settings\Settings.xml" -Value $DduConfig -Force

# set ddu config to read only
Set-ItemProperty -Path "$env:ProgramData\Cullewie\Work\ddu\Settings\Settings.xml" -Name IsReadOnly -Value $true

# prevent downloads of drivers from windows update
cmd /c "reg add `"HKLM\Software\Microsoft\Windows\CurrentVersion\DriverSearching`" /v `"SearchOrderConfig`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# create ddumanual ps1 file
$DDU = @'
# SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host

# remove safe mode boot
cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"

Write-Host "DDU MANUAL`n"

# open ddu
Start-Process -Wait "$env:ProgramData\Cullewie\Work\ddu\Display Driver Uninstaller.exe"
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\ddumanual.ps1" -Value $DDU -Force

# install runonce ddumanual ps1 file to run in safe boot
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*ddumanual`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:ProgramData\Cullewie\Work\ddumanual.ps1`" /f >nul 2>&1"

# turn on safe boot
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"

Write-Host "RESTARTING`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00

exit

      }
    } } else { Write-Host "Invalid input. Please select a valid option (1-2)." } }