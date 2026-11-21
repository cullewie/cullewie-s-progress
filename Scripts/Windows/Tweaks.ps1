# Windows tweaks adapted from opcin's "YUKSEK FPS" optimization script.
# Removed: restore point creation, the no-op Razer step, the ping check and the
# NVIDIA, Copilot and power plan steps that other toolkit scripts already do.
# System Restore is turned off so Windows never creates restore points.

$ProgressPreference = 'SilentlyContinue'
Clear-Host
Write-Host "Windows Tweaks...`n"

function Set-Reg {
    param($Path, $Name, $Value, $Type = "DWord")
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Name -eq "(Default)") {
        Set-ItemProperty -Path $Path -Name "(default)" -Value $Value -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -ErrorAction SilentlyContinue
    }
}

Write-Host "System Restore off"
Disable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" -Name "DisableSR" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" -Name "DisableConfig" -Value 1

Write-Host "Activity history off"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0

Write-Host "BitLocker off"
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    if ($bl -and $bl.VolumeStatus -ne "FullyDecrypted") { Disable-BitLocker -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue | Out-Null }
}
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker" -Name "PreventDeviceEncryption" -Value 1

Write-Host "Consumer features and suggestions off"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableConsumerAccountStateContent" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableCloudOptimizedContent" -Value 1
Set-Reg -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_ShowRecommended" -Value 0

Write-Host "Delivery Optimization off"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0

Write-Host "Taskbar End Task"
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarEndTask" -Value 1

Write-Host "Folder type discovery off"
Set-Reg -Path "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" -Name "FolderType" -Type "String" -Value "NotSpecified"

Write-Host "Privacy"
$consentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
foreach ($store in "location","userNotificationListener","userAccountInformation","contacts","appointments","phoneCall","phoneCallHistory","email","chat","radios","appDiagnostics") {
    Set-Reg -Path "$consentPath\$store" -Name "Value" -Type "String" -Value "Deny"
}
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0

Write-Host "Telemetry services off"
Set-Service -Name "RemoteRegistry" -StartupType Manual -ErrorAction SilentlyContinue
Set-Service -Name "MapsBroker" -StartupType Manual -ErrorAction SilentlyContinue
foreach ($svc in "DiagTrack","dmwappushservice") {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

Write-Host "Widgets package removed"
Get-AppxPackage -AllUsers *WebExperience* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Write-Host "WPBT and reserved storage off"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWPBT" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0

Write-Host "Prefer IPv4"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 32

Write-Host "Edge background features off"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HardwareAccelerationModeEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0
foreach ($svc in "MicrosoftEdgeElevationService","edgeupdate","edgeupdatem") {
    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

Write-Host "OneDrive removed"
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
if (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") {
    Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait
}

Write-Host "Classic context menu"
Set-Reg -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34a9-4b08-ac74-0705a6e54656}\InprocServer32" -Name "(Default)" -Type "String" -Value ""

Write-Host "Win32 priority separation"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38

Write-Host "Taskbar, Explorer and dark theme"
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
Set-Reg -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type "String" -Value "0"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0

Write-Host "Sound ducking and startup sound off"
Set-Reg -Path "HKCU:\Software\Microsoft\Multimedia\Audio" -Name "UserDuckingPreference" -Value 3
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Value 1

Write-Host "Mouse acceleration off"
Set-Reg -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Type "String" -Value "0"
Set-Reg -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Type "String" -Value "0"
Set-Reg -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Type "String" -Value "0"

Write-Host "Game settings: Game DVR off, Game Mode on, fullscreen optimizations, HAGS on"
Set-Reg -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1
Set-Reg -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 0
Set-Reg -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 0
Remove-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -ErrorAction SilentlyContinue
Set-Reg -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -Name "DirectXUserGlobalSettings" -Type "String" -Value "VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;"
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 4294967295
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Value 8
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Value 6
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Scheduling Category" -Type "String" -Value "High"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -ErrorAction SilentlyContinue

Write-Host "Nagle off"
foreach ($interface in Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces") {
    Set-Reg -Path $interface.PSPath -Name "TcpAckFrequency" -Value 1
    Set-Reg -Path $interface.PSPath -Name "TCPNoDelay" -Value 1
}

Write-Host "Interrupt steering on the toolkit power plan"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\48672f38-7a9a-4bb2-8bf8-3d85be19de4e\2bfc24f9-5ea2-4801-8213-3dbae01aa39d" -Name "Attributes" -Value 2
powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 48672f38-7a9a-4bb2-8bf8-3d85be19de4e 2bfc24f9-5ea2-4801-8213-3dbae01aa39d 5 2>$null
powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 48672f38-7a9a-4bb2-8bf8-3d85be19de4e 2bfc24f9-5ea2-4801-8213-3dbae01aa39d 5 2>$null

Write-Host "DirectX and Visual C++ runtimes"
foreach ($id in "Microsoft.DirectX","Microsoft.VCRedist.2015+.x64","Microsoft.VCRedist.2015+.x86") {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements >$null 2>&1
}

Write-Host "Temporary files and Disk Cleanup"
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
# Downloads, Recycle Bin and File History versions hold user files; Disk Cleanup leaves them alone.
$keep = "DownloadsFolder","Recycle Bin","User file versions"
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches" -ErrorAction SilentlyContinue |
    Where-Object { $keep -notcontains $_.PSChildName } |
    ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Type DWord -Value 2 -ErrorAction SilentlyContinue }
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -ErrorAction SilentlyContinue

Write-Host "Done.`n"
exit
