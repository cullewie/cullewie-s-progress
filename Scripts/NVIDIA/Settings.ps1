# NVIDIA in one step: driver settings and Profile Inspector profile, P0 state, highest refresh rate (Refresh-Rate.ps1,
# which AMD cards run on their own), then full-screen scaling and digital
# vibrance (two questions, through Scripts/GPU/Display-Options.ps1, which AMD and the vibrance sign-in task also use).
# -SkipDisplay: no questions here. The full setup uses it and asks them at the very end, after every other setting;
# live mode uses it and leaves scaling and vibrance as they are.
param([switch]$SkipDisplay)
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

        # LOG: everything shown on screen also goes to the log; any error is printed and the script exits with code 1
        Start-Transcript -Path "$env:ProgramData\Cullewie\Work\nvidia-settings.log" -Force | Out-Null
        trap { Write-Host "NVIDIA Settings failed: $_" -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

        while ($true) {
        $choice = '1'
        if ($choice -match '^[1]$') {
        switch ($choice) {
        1 {

Clear-Host

# unblock drs files
$path = "C:\ProgramData\NVIDIA Corporation\Drs"
Get-ChildItem -Path $path -Recurse | Unblock-File

# set physx to gpu
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"NvCplPhysxAuto`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# enable developer settings
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"NvDevToolsVisible`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

# allow access to the gpu performance counters to all users
$subkeys = Get-ChildItem -Path "Registry::HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Force -ErrorAction SilentlyContinue
foreach($key in $subkeys){
if ($key.Name -match '\\\d{4}$'){
reg add "$key" /v "RmProfilingAdminOnly" /t REG_DWORD /d "0" /f | Out-Null
}
}
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"RmProfilingAdminOnly`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# disable show notification tray icon
cmd /c "reg add `"HKCU\Software\NVIDIA Corporation\NvTray`" /v `"StartOnLogin`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# enable nvidia legacy sharpen
cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Services\nvlddmkm\Parameters\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# new folder
New-Item -Path "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# download nvidia profile inspector
IWR "https://github.com/cullewie/cullewie-s-progress/releases/download/files/inspector.exe" -OutFile "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector\Nvidia Profile Inspector.exe"
if ((Get-FileHash "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector\Nvidia Profile Inspector.exe" -Algorithm SHA256).Hash -ne '071f38bfeec4fab0a33261f7fa010940e2c3c96fb21f03d18d490110ddb90b03') { throw 'inspector.exe SHA-256 mismatch; download stopped.' }

# create desktop shortcut
$WshShell = New-Object -comObject WScript.Shell
$Desktop = (New-Object -ComObject Shell.Application).Namespace('shell:Desktop').Self.Path
$Shortcut = $WshShell.CreateShortcut("$Desktop\Nvidia Profile Inspector.lnk")
$Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector\Nvidia Profile Inspector.exe"
$Shortcut.WorkingDirectory = "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector"
$Shortcut.Save()

# create start menu shortcut
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Nvidia Profile Inspector.lnk")
$Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector\Nvidia Profile Inspector.exe"
$Shortcut.WorkingDirectory = "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector"
$Shortcut.Save()

# set config for inspector
$nipfile = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executables/>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter V3</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Application Mode</SettingNameInfo>
        <SettingID>294973784</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Application State</SettingNameInfo>
        <SettingID>279476687</SettingID>
        <SettingValue>4</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Global Feature</SettingNameInfo>
        <SettingID>278196567</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Global Mode</SettingNameInfo>
        <SettingID>278196727</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Indicator Overlay</SettingNameInfo>
        <SettingID>268604728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum Pre-Rendered Frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Ultra Low Latency - CPL State</SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Ultra Low Latency - Enabled</SettingNameInfo>
        <SettingID>277041152</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred Refresh Rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync - Smooth AFR Behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync - Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vulkan/OpenGL Present Method</SettingNameInfo>
        <SettingID>550932728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Gamma Correction</SettingNameInfo>
        <SettingID>276652957</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Mode</SettingNameInfo>
        <SettingID>276757595</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Setting</SettingNameInfo>
        <SettingID>282555346</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filter - Optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filter - Sample Optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filtering - Mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filtering - Setting</SettingNameInfo>
        <SettingID>270426537</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Negative LOD Bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Trilinear Optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>CUDA - Force P2 State</SettingNameInfo>
        <SettingID>1343646814</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
	  <ProfileSetting>
        <SettingNameInfo>CUDA - Sysmem Fallback Policy</SettingNameInfo>
        <SettingID>283962569</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Power Management - Mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader Cache - Cache Size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Threaded Optimization</SettingNameInfo>
        <SettingID>549528094</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>OpenGL GDI Compatibility</SettingNameInfo>
        <SettingID>544392611</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\inspector.nip" -Value $nipfile -Force

# import nip (Low Latency Mode: Off)
$inspector = "$env:SystemDrive\Program Files (x86)\Nvidia Profile Inspector\Nvidia Profile Inspector.exe"
$importArgs = "-silentImport -silent `"$env:ProgramData\Cullewie\Work\inspector.nip`""
# right after a fresh driver install (or with no driver) the driver is not loaded until a restart, and Profile Inspector
# crashes; then import at the next sign-in instead (HKLM RunOnce runs elevated)
$gpu = Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'PCI\\VEN_10DE%'" | Where-Object { @($_.CompatibleID) -match '^PCI\\CC_03' } | Select-Object -First 1
$driverReady = $gpu -and $gpu.ConfigManagerErrorCode -eq 0 -and $gpu.Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX|TITAN' -and (Test-Path "$env:SystemRoot\System32\nvapi64.dll")
if (-not $driverReady) {
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'CullewieNvidiaProfile' -Value "`"$inspector`" $importArgs"
    Write-Host 'NVIDIA driver is not loaded yet (restart pending): the profile is imported at the next sign-in.' -ForegroundColor Yellow
}
else {
    Write-Host "Importing profile: $(([xml]$nipfile).ArrayOfProfile.Profile.Settings.ProfileSetting.Count) settings"
    $import = Start-Process -Wait -PassThru $inspector -ArgumentList $importArgs
    if ($import.ExitCode -ne 0) { Write-Host "Profile Inspector exit code $($import.ExitCode): open it and check the Base Profile." -ForegroundColor Yellow }
    else { Write-Host 'NVIDIA profile: imported.' -ForegroundColor Green }
}

# P0 state: the GPU always stays at its highest performance state (max boost clock)
Write-Host 'P0 state: on'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' } |
    ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name 'DisableDynamicPstate' -Value 1 -Type DWord -ErrorAction SilentlyContinue }

# highest refresh rate: a fresh driver often starts the display at 60 Hz
$refreshRate = Join-Path $PSScriptRoot '..\GPU\Refresh-Rate.ps1'
if (Test-Path $refreshRate) {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $refreshRate
    if ($LASTEXITCODE -ne 0) { Write-Host "Refresh rate: $LASTEXITCODE display(s) could not be changed, see above." -ForegroundColor Yellow }
}

# full-screen scaling and digital vibrance
$displayOptions = Join-Path $PSScriptRoot '..\GPU\Display-Options.ps1'
if ($SkipDisplay) { Write-Host 'Scaling and vibrance: skipped (no questions in this mode).' }
elseif (Test-Path $displayOptions) {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $displayOptions
    if ($LASTEXITCODE -ne 0) { Write-Host "Scaling and vibrance: $LASTEXITCODE step(s) failed, see above." -ForegroundColor Yellow }
}
Write-Host 'NVIDIA Settings: done.' -ForegroundColor Green
Stop-Transcript | Out-Null

exit 0

          }
        } } else { Write-Host "Invalid input. Please select a valid option (1)." } }