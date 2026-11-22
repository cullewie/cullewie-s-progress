# Removes preinstalled Windows apps, optional capabilities and legacy features that a gaming PC does not need.
# Only what is named in the lists below is removed: apps the user installed (Claude, ChatGPT, games, Store apps)
# are never touched. Kept on purpose: Microsoft Store, App Installer (winget), Xbox and Game Bar, WSL/Hyper-V.
# -DryRun only writes what would be removed to bloatware-dryrun.txt.
param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$log = Join-Path $env:ProgramData 'Cullewie\Work\bloatware-dryrun.txt'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
if ($DryRun) { Set-Content -Path $log -Value "Dry run $(Get-Date -Format s)" -Encoding UTF8 }
function Write-Plan([string]$Kind, [string]$Name) { if ($DryRun) { Add-Content -Path $log -Value "$Kind`t$Name" -Encoding UTF8 } }

Write-Host 'Removing apps...'
$removeApps = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.BingFinance', 'Microsoft.BingSports',
    'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsAlarms',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder', 'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo', 'Microsoft.YourPhone', 'Microsoft.OutlookForWindows', 'microsoft.windowscommunicationsapps',
    'MicrosoftTeams', 'MSTeams', 'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10', 'Microsoft.Copilot',
    'Microsoft.Windows.DevHome', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp', 'Microsoft.Messaging', 'Microsoft.Microsoft3DViewer',
    'Microsoft.3DBuilder', 'Microsoft.Office.OneNote', 'Microsoft.Wallet',
    'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftWindows.CrossDevice'
)
foreach ($app in Get-AppxPackage -AllUsers | Where-Object { $removeApps -contains $_.Name }) {
    Write-Plan 'app' $app.Name
    if (-not $DryRun) { $app | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
}
# stop Windows from installing them again for new accounts
foreach ($app in Get-AppxProvisionedPackage -Online | Where-Object { $removeApps -contains $_.DisplayName }) {
    Write-Plan 'provisioned' $app.DisplayName
    if (-not $DryRun) { $app | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null }
}

Write-Host 'Removing optional capabilities...'
$removeCapabilities = @(
    'App.StepsRecorder*', 'App.Support.QuickAssist*', 'Browser.InternetExplorer*', 'MathRecognizer*',
    'Microsoft.Windows.WordPad*', 'OneCoreUAP.OneSync*', 'Print.Fax.Scan*', 'Print.Management.Console*', 'Hello.Face*'
)
foreach ($cap in Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' }) {
    $name = $cap.Name
    if (-not ($removeCapabilities | Where-Object { $name -like $_ })) { continue }
    Write-Plan 'capability' $name
    if (-not $DryRun) { try { Remove-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null } catch { } }
}

Write-Host 'Turning off legacy features...'
$removeFeatures = @(
    'Internet-Explorer-Optional-amd64', 'SMB1Protocol', 'SMB1Protocol-Client', 'SMB1Protocol-Server',
    'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2', 'WorkFolders-Client',
    'Printing-XPSServices-Features', 'Recall'
)
foreach ($feature in Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' -and $removeFeatures -contains $_.FeatureName }) {
    $name = $feature.FeatureName
    Write-Plan 'feature' $name
    if (-not $DryRun) { try { Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null } catch { } }
}

Write-Host 'Removing legacy apps...'
$uninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
function Remove-MsiProduct([string]$Like) {
    foreach ($p in Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Like }) {
        Write-Plan 'program' $p.DisplayName
        if (-not $DryRun) { Start-Process 'msiexec.exe' -ArgumentList "/x $($p.PSChildName) /qn /norestart" -Wait -NoNewWindow }
    }
}
Remove-MsiProduct '*Update for x64-based Windows Systems*'
Remove-MsiProduct '*Microsoft Update Health Tools*'
Write-Plan 'program' 'OneDrive'
Write-Plan 'program' 'Remote Desktop Connection'
Write-Plan 'program' 'braille driver (brlapi)'
if (-not $DryRun) {
    # braille driver
    cmd /c "sc stop `"brlapi`" >nul 2>&1"
    cmd /c "sc delete `"brlapi`" >nul 2>&1"
    cmd /c "takeown /f `"$env:SystemRoot\brltty`" /r /d y >nul 2>&1"
    cmd /c "icacls `"$env:SystemRoot\brltty`" /grant *S-1-5-32-544:F /t >nul 2>&1"
    Remove-Item "$env:SystemRoot\brltty" -Recurse -Force -ErrorAction SilentlyContinue
    cmd /c "reg delete `"HKLM\SYSTEM\ControlSet001\Services\uhssvc`" /f >nul 2>&1"
    Unregister-ScheduledTask -TaskName PLUGScheduler -Confirm:$false -ErrorAction SilentlyContinue

    # OneDrive
    Stop-Process -Force -Name OneDrive -ErrorAction SilentlyContinue
    cmd /c "$env:SystemRoot\System32\OneDriveSetup.exe -uninstall >nul 2>&1"
    Get-ChildItem -Path "$env:ProgramFiles*\Microsoft OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive" -Filter 'OneDriveSetup.exe' -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { Start-Process -Wait $_.FullName -ArgumentList '/uninstall /allusers' -WindowStyle Hidden -ErrorAction SilentlyContinue }
    cmd /c "$env:SystemRoot\SysWOW64\OneDriveSetup.exe -uninstall >nul 2>&1"
    Get-ScheduledTask | Where-Object { $_.TaskName -match 'OneDrive' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    # Remote Desktop Connection: the uninstaller opens a window, close it as soon as it appears
    Start-Process 'mstsc' -ArgumentList '/Uninstall' -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 100; $i++) {
        $p = Get-Process -Name mstsc -ErrorAction SilentlyContinue
        if (-not $p) { break }
        if ($p.MainWindowHandle -ne 0) { Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue; break }
        Start-Sleep -Milliseconds 100
    }
    Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue
}

if ($DryRun) { Write-Host "Dry run: nothing was removed. List: $log" -ForegroundColor Yellow } else { Write-Host 'Done.' -ForegroundColor Green }
exit 0
