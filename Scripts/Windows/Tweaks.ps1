# Windows tweaks: Bloatware, Tweaks and Extras in one script, in this order:
#  1. Removes preinstalled Windows apps, optional capabilities and legacy features a gaming PC does not need. Only what
#     is named in the lists is removed: apps the user installed (Claude, ChatGPT, games, Store apps) are never touched.
#     The apps themselves are kept: Microsoft Store, App Installer (winget), the Xbox app, Gaming Services, WSL/Hyper-V.
#     But with the default Services list (Windows Update, BITS and Xbox services off) Store and Game Pass downloads do
#     not work; choose -Apps store or xbox (also in Services) for them. Also removed: Microsoft GameInput, the Game Bar overlay, Copilot, Widgets, OneDrive, Windows Hello Face,
#     Update Health Tools.
#  2. General tweaks: privacy, telemetry, Explorer, game settings, Nagle, MSI mode, HDCP, memory compression,
#     Visual C++ runtimes. System Restore is turned off so Windows never creates restore points.
#     BitLocker is turned off (the system drive is decrypted).
#  3. Extra settings: Game Bar off, new Start menu, Edge kept (WebView2 draws the Start search box), Notepad, Control
#     Panel and Settings options, audio Enhancements tab, device and network power saving/wake off (keyboard and mouse
#     cannot wake the PC), IPv4 only with file sharing/SMB client and server unbound, disk write-cache flushing off
#     (power loss can cost data), dark theme (the desktop keeps its wallpaper). Where 2 and 3 set the same value, 3 wins.
#     Deliberately aggressive, also: display scaling fixed at 100%, all toast notifications off, Store auto-update and
#     background apps off, Automatic Maintenance and scheduled defrag/retrim off, app access to the document/picture/
#     music/video libraries and passkeys denied, Lock and Sleep hidden in the power menu, Alt+Shift layout switching off.
# -DryRun: only writes what step 1 would remove to bloatware-dryrun.txt and stops; nothing is changed.
# -Apps store: Store auto-update and background apps stay on; Windows Update gets the monthly update only.
#       xbox:  the same, and GameInput, the Game Bar and IPv6 (Teredo, for Xbox party chat and multiplayer) stay too.
param([switch]$DryRun, [ValidateSet('off', 'store', 'xbox')][string]$Apps = 'off')

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$log = Join-Path $env:ProgramData 'Cullewie\Work\bloatware-dryrun.txt'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
if ($DryRun) { Set-Content -Path $log -Value "Dry run $(Get-Date -Format s)" -Encoding UTF8 }
function Write-Plan([string]$Kind, [string]$Name) { if ($DryRun) { Add-Content -Path $log -Value "$Kind`t$Name" -Encoding UTF8 } }

# what this run finds and removes, for Vanilla Mode to bring back: each item is listed before it is removed. A list an
# earlier run left is kept and this run's items are added to it (an earlier run, e.g. Xbox & Store, may have listed
# nothing; a later All-in must still be able to list what it removes), each name once.
$inventoryPath = Join-Path $env:ProgramData 'Cullewie\Work\removed-inventory.json'
$removedInventory = [ordered]@{ apps = @(); capabilities = @(); features = @(); programs = @() }
function Save-RemovedInventory([System.Collections.IDictionary]$Inventory, [string]$Path) {
    $merged = [ordered]@{ apps = @(); capabilities = @(); features = @(); programs = @() }
    if (Test-Path -LiteralPath $Path) {
        try {
            $old = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            foreach ($k in @($merged.Keys)) { $merged[$k] = @($old.$k | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
        }
        catch { }
    }
    foreach ($k in @($merged.Keys)) { $merged[$k] = @(@($merged[$k]) + @($Inventory[$k]) | Where-Object { $_ } | Select-Object -Unique) }
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($merged | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    $true
}
# removed further down (Widgets section, Game Bar section), recorded here
foreach ($pkg in 'MicrosoftWindows.Client.WebExperience', 'Microsoft.XboxGamingOverlay') {
    if ($pkg -eq 'Microsoft.XboxGamingOverlay' -and $Apps -eq 'xbox') { continue }
    if (@(Get-AppxPackage -AllUsers $pkg | Where-Object { @($_.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count }).Count) { $removedInventory.apps += $pkg }
}

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
# All-in and Only Store Mode also remove the Xbox app, Gaming Services and the Xbox Identity Provider: with the Xbox
# services off they cannot work, and Gaming Services kept running in the background. Xbox & Store keeps them (Store-Xbox
# installs what is missing). Listed below like every other app, so Vanilla Mode brings them back.
if ($Apps -ne 'xbox') { $removeApps += 'Microsoft.GamingApp', 'Microsoft.GamingServices', 'Microsoft.XboxIdentityProvider' }
# one line per listed app: already gone is a pass, not an error. A package left only "staged" for the
# system account is not installed for anyone, so it counts as removed too.
$installed = @(Get-AppxPackage -AllUsers | Where-Object { $removeApps -contains $_.Name -and @($_.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count })
foreach ($name in $removeApps) {
    $app = $installed | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if (-not $app) { Write-Host "  ok    $name (already removed)" -ForegroundColor DarkGray; continue }
    Write-Plan 'app' $name
    $removedInventory.apps += $name
    if ($DryRun) { continue }
    $app | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $left = @(Get-AppxPackage -AllUsers $name | Where-Object { @($_.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count })
    if ($left.Count) { Write-Host "  FAIL  $name (still installed)" -ForegroundColor Red } else { Write-Host "  ok    $name (removed)" -ForegroundColor Green }
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
    $removedInventory.capabilities += $name
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
    $removedInventory.features += $name
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
if ($Apps -ne 'xbox' -and @(Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Microsoft GameInput*' }).Count) { $removedInventory.programs += 'GameInput' }
if ((Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") -or (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe")) { $removedInventory.programs += 'OneDrive' }
if (Get-Command mstsc -ErrorAction SilentlyContinue) { $removedInventory.programs += 'RemoteDesktop' }
if (-not $DryRun) { if (Save-RemovedInventory $removedInventory $inventoryPath) { Write-Host "Removed items listed for Vanilla Mode: $inventoryPath" } }
if ($Apps -ne 'xbox') { Remove-MsiProduct '*Microsoft GameInput*' }   # Game Pass games need it
Remove-MsiProduct '*Update for x64-based Windows Systems (KB5001716)*'   # exact KB, a bare wildcard could match other servicing updates
Remove-MsiProduct '*Microsoft Update Health Tools*'
Write-Plan 'program' 'OneDrive'
Write-Plan 'program' 'Remote Desktop Connection'
Write-Plan 'program' 'braille driver (brlapi)'
if (-not $DryRun) {
    # braille driver
    cmd /c "sc stop `"brlapi`" >nul 2>&1"
    cmd /c "sc delete `"brlapi`" >nul 2>&1"
    # owner by SID through icacls: takeown asks a yes/no whose answer letter depends on the Windows display language
    cmd /c "icacls `"$env:SystemRoot\brltty`" /setowner *S-1-5-32-544 /T /C >nul 2>&1"
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
    # Windows' "OneDriveSetup.exe /thfirstsetup" startup entry reinstalls OneDrive at the next sign-in: remove it for this
    # user and in the default profile that new users are copied from
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
    cmd /c "reg load HKU\CullewieDefault `"$env:SystemDrive\Users\Default\NTUSER.DAT`" >nul 2>&1"
    cmd /c "reg delete `"HKU\CullewieDefault\Software\Microsoft\Windows\CurrentVersion\Run`" /v OneDriveSetup /f >nul 2>&1"
    [gc]::Collect()
    cmd /c "reg unload HKU\CullewieDefault >nul 2>&1"

    # Remote Desktop Connection: the uninstaller opens a window, close it as soon as it appears
    # already removed on a second run: nothing to start
    if (Get-Command mstsc -ErrorAction SilentlyContinue) { Start-Process 'mstsc' -ArgumentList '/Uninstall' -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt 100; $i++) {
        $p = Get-Process -Name mstsc -ErrorAction SilentlyContinue
        if (-not $p) { break }
        if ($p.MainWindowHandle -ne 0) { Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue; break }
        Start-Sleep -Milliseconds 100
    }
    Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue
}

if ($DryRun) { Write-Host "Dry run: nothing was removed or changed. List: $log" -ForegroundColor Yellow; exit 0 }

# ---- general tweaks ----
$ProgressPreference = 'SilentlyContinue'
Write-Host "Windows Tweaks...`n"

Write-Host "Widgets off"
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests`" /v `"value`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Dsh`" /v `"AllowNewsAndInterests`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
Stop-Process -Force -Name Widgets -ErrorAction SilentlyContinue
Stop-Process -Force -Name WidgetService -ErrorAction SilentlyContinue

Write-Host "Copilot off"
Stop-Process -Name "Copilot" -Force -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers *Copilot* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
# provisioned package too, so new or reset user profiles do not get it back
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*Copilot*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
cmd /c "reg add `"HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot`" /v `"TurnOffWindowsCopilot`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot`" /v `"TurnOffWindowsCopilot`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

function Set-Reg {
    param($Path, $Name, $Value, $Type = "DWord")
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Name -eq "(Default)") {
        Set-ItemProperty -Path $Path -Name "(default)" -Value $Value -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -ErrorAction SilentlyContinue
    }
}
# drops one [key] block (its header and value lines, up to the blank line after it) from .reg text
function Remove-RegKeyBlock([string]$Text, [string]$Key) {
    [regex]::Replace($Text, '(?im)^\[' + [regex]::Escape($Key) + '\]\r?\n(?:[^\[\r\n][^\r\n]*\r?\n)*(?:\r?\n)?', '')
}
# -Apps store / xbox turn Windows Update back on: only the monthly cumulative update, no new Windows version,
# no drivers, no optional or preview updates (Windows 11 has no separate security-only update)
function Set-AppsUpdatePolicy([string]$PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
                              [string]$UxKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings',
                              [string]$DisplayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion) {
    Set-Reg -Path $PolicyKey -Name 'TargetReleaseVersion' -Value 1
    Set-Reg -Path $PolicyKey -Name 'ProductVersion' -Type 'String' -Value 'Windows 11'
    Set-Reg -Path $PolicyKey -Name 'TargetReleaseVersionInfo' -Type 'String' -Value $DisplayVersion
    Set-Reg -Path $PolicyKey -Name 'ExcludeWUDriversInQualityUpdate' -Value 1
    Set-Reg -Path $PolicyKey -Name 'AllowOptionalContent' -Value 0
    Set-Reg -Path $PolicyKey -Name 'SetAllowOptionalContent' -Value 0
    Set-Reg -Path $UxKey -Name 'IsContinuousInnovationOptedIn' -Value 0
}

# ---- appearance backup, for Vanilla Mode ----
# Before anything below changes the look of Windows, the user's current values are saved; Vanilla.ps1 writes exactly
# these back. Which values: every one this script writes (Set-Reg calls and .reg blocks, read from this file) under the
# theme, colour, visual effect, scaling, taskbar, Start menu, Explorer and context menu keys. Saved only when no backup
# exists yet, so a second run never replaces the user's look with this script's own.
$appearanceKeys = @(
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes(\\|$)',
    '^HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize$',
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\(Accent|Advanced|VisualEffects)(\\|$)',
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\DWM$',
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Lighting$',
    '^HKEY_CURRENT_USER\\Control Panel\\(Desktop|Colors)(\\|$)',
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\(Search|Start)$',
    '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\CloudStore\\',
    '^HKEY_CURRENT_USER\\Software\\Classes\\CLSID\\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2\}',
    '^HKEY_CURRENT_USER\\SOFTWARE\\Microsoft\\CTF\\LangBar$'
)
function Get-AppearanceEntries([string]$Text, [string[]]$KeyPatterns) {
    $found = [ordered]@{}
    $add = {
        param($key, $value)
        $k = $key -replace '^HKCU:?\\', 'HKEY_CURRENT_USER\' -replace '^HKLM:?\\', 'HKEY_LOCAL_MACHINE\' -replace '\?', '$'
        if (@($KeyPatterns | Where-Object { $k -match $_ }).Count) { $found["$k|$value".ToLowerInvariant()] = [pscustomobject]@{ Key = $k; Value = $value } }
    }
    foreach ($m in [regex]::Matches($Text, 'Set-Reg -Path "(HK[^"]+)" -Name "([^"]+)"')) {
        & $add $m.Groups[1].Value $(if ($m.Groups[2].Value -eq '(Default)') { '' } else { $m.Groups[2].Value })
    }
    $current = $null
    foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^\[(HKEY_[^\]]+)\]\s*$') { $current = $Matches[1]; continue }
        if ($line -match '^\[') { $current = $null; continue }
        if (-not $current) { continue }
        if ($line -match '^"([^"]+)"=') { & $add $current $Matches[1] }
        elseif ($line -match '^@=') { & $add $current '' }
    }
    @($found.Values)
}
function Open-RegKey([string]$Key, [bool]$Create) {
    $hive = if ($Key -like 'HKEY_LOCAL_MACHINE\*') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $sub = $Key -replace '^HKEY_[A-Z_]+\\', ''
    if ($Create) { $hive.CreateSubKey($sub) } else { $hive.OpenSubKey($sub) }
}
function Save-AppearanceBackup([object[]]$Entries, [string]$Path) {
    if (Test-Path -LiteralPath $Path) { return $false }
    $saved = foreach ($e in $Entries) {
        $key = Open-RegKey $e.Key $false
        $item = [ordered]@{ Key = $e.Key; Value = $e.Value; KeyExisted = $null -ne $key; Exists = $false; Kind = $null; Data = $null }
        if ($key -and ($key.GetValueNames() -contains $e.Value)) {
            $kind = $key.GetValueKind($e.Value)
            $raw = $key.GetValue($e.Value, $null, 'DoNotExpandEnvironmentNames')
            $item.Exists = $true; $item.Kind = [string]$kind
            $item.Data = switch ($kind) { 'Binary' { [Convert]::ToBase64String([byte[]]$raw) } 'MultiString' { ,@($raw) } default { $raw } }
        }
        if ($key) { $key.Close() }
        [pscustomobject]$item
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    ConvertTo-Json -InputObject @($saved) -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
    $true
}
$appearanceBackup = Join-Path $env:ProgramData ('Cullewie\Work\appearance-backup-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '.json')
$appearanceEntries = Get-AppearanceEntries ([IO.File]::ReadAllText($PSCommandPath)) $appearanceKeys
if (Save-AppearanceBackup $appearanceEntries $appearanceBackup) { Write-Host "Appearance: current settings saved for Vanilla Mode ($($appearanceEntries.Count) values)" }
else { Write-Host 'Appearance: a saved copy already exists (kept, so Vanilla Mode restores the original look)' }

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

Write-Host "Delivery Optimization: HTTP only, no peer-to-peer (Store downloads keep working)"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0

Write-Host "Folder type discovery off"
Set-Reg -Path "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" -Name "FolderType" -Type "String" -Value "NotSpecified"

Write-Host "Privacy"
$consentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
foreach ($store in "location","userNotificationListener","userAccountInformation","contacts","appointments","phoneCall","phoneCallHistory","email","chat","radios","appDiagnostics") {
    Set-Reg -Path "$consentPath\$store" -Name "Value" -Type "String" -Value "Deny"
}
# background apps off for all apps (not with -Apps: Store and Xbox downloads and sign-in run in the background)
if ($Apps -eq 'off') {
    Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
    Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2
}
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BackgroundAppGlobalToggle" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0

Write-Host "Telemetry services off"
Set-Service -Name "MapsBroker" -StartupType Manual -ErrorAction SilentlyContinue
foreach ($svc in "DiagTrack","dmwappushservice") {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

Write-Host "Widgets package removed"
Get-AppxPackage -AllUsers *WebExperience* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Write-Host "Reserved storage off"
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
powercfg /setactive scheme_current 2>$null   # changed values apply only when the plan is re-activated

# Device and GPU extras. Tweaks runs after the NVIDIA driver, so the GPU keys below already exist.
Write-Host "GPU: MSI mode on, HDCP off"
foreach ($gpu in Get-PnpDevice -Class Display -ErrorAction SilentlyContinue) {
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" -Name "MSISupported" -Value 1
}
# HDCP off: protected video (for example Netflix in 4K) may refuse to play
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' } |
    ForEach-Object { Set-Reg -Path $_.PSPath -Name "RMHdcpKeyglobZero" -Value 1 }


Write-Host "Memory compression off"
Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue | Out-Null

# no legacy DirectX package: Windows 11 already has DirectX 12, and games that need old DirectX 9 files install them
Write-Host "Visual C++ runtimes"
foreach ($id in "Microsoft.VCRedist.2015+.x64","Microsoft.VCRedist.2015+.x86") {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements >$null 2>&1
}

# Only the temp folders on the system drive. No Disk Cleanup (cleanmgr /sagerun): it always scans every drive,
# USB sticks included (its /d option is ignored with /sagerun), and it hung there.
Write-Host "Temporary files ($env:SystemDrive only)"
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue


# ---- extra settings ----
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$work = Join-Path $env:ProgramData 'Cullewie\Work'
New-Item -ItemType Directory -Path $work -Force | Out-Null

# Runs $Command once as TrustedInstaller (the service is pointed at powershell for one start).
# Never kills a busy Windows Modules Installer, waits until the command has finished,
# and checks that the real TrustedInstaller path is back (Windows Update and DISM depend on it).
function Run-Trusted([string]$Command) {
    $default = "$env:SystemRoot\servicing\TrustedInstaller.exe"
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller'
    $done = Join-Path $env:ProgramData ('Cullewie\Work\trusted-' + [guid]::NewGuid().ToString('N') + '.done')
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Service TrustedInstaller).Status -ne 'Stopped') {
        # idle: stop it politely; busy with servicing (TiWorker) or still starting: wait
        if (-not (Get-Process TiWorker -ErrorAction SilentlyContinue)) { Stop-Service TrustedInstaller -ErrorAction SilentlyContinue }
        if ((Get-Date) -gt $deadline) { Write-Host 'TrustedInstaller is busy with Windows servicing; this step was skipped.' -ForegroundColor Yellow; $global:CullewieTrustedFailed = $true; return }
        Start-Sleep -Seconds 2
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("$Command`nSet-Content -LiteralPath '$done' -Value ok"))
    try {
        sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -NoProfile -EncodedCommand $encoded" | Out-Null
        sc.exe start TrustedInstaller | Out-Null
        # 1053 ("did not respond in time") is expected: powershell is not a service. Any other error: it never ran, don't wait.
        $wait = if ($LASTEXITCODE -in 0, 1053) { (Get-Date).AddMinutes(3) } else { Get-Date }
        while (-not (Test-Path -LiteralPath $done) -and (Get-Date) -lt $wait) { Start-Sleep -Milliseconds 500 }
    }
    finally {
        for ($i = 0; $i -lt 10; $i++) {
            sc.exe config TrustedInstaller binPath= "`"$default`"" | Out-Null
            if ((Get-ItemProperty $key).ImagePath -match 'servicing\\TrustedInstaller\.exe"?$') { break }
            Start-Sleep -Seconds 1
        }
    }
    if ((Get-ItemProperty $key).ImagePath -notmatch 'servicing\\TrustedInstaller\.exe"?$') {
        Write-Host "TrustedInstaller path was NOT restored. Run as admin: sc.exe config TrustedInstaller binPath= `"$default`"" -ForegroundColor Red
        $global:CullewieTrustedBroken = $true
    }
    if (Test-Path -LiteralPath $done) { Remove-Item -LiteralPath $done -Force }
    else { Write-Host 'A TrustedInstaller step did not finish in time; it may not be applied.' -ForegroundColor Yellow; $global:CullewieTrustedFailed = $true }
}
function Import-Reg([string]$Name, [string]$Content) {
    $file = Join-Path $work "$Name.reg"
    Set-Content -Path $file -Value $Content -Force
    Start-Process -Wait regedit.exe -ArgumentList "/S `"$file`"" -WindowStyle Hidden
}
# settings.dat of a Store app is a registry hive; load it, import, unload
function Import-AppSettings([string]$SettingsDat, [string]$Name, [string]$Content) {
    if (-not (Test-Path $SettingsDat)) { return }
    $file = Join-Path $work "$Name.reg"
    Set-Content -Path $file -Value $Content -Force
    reg load 'HKLM\Settings' $SettingsDat 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        reg import $file 2>$null | Out-Null
        # an unload that fails leaves the app's settings locked until restart (for Client.CBS: Start and search), so retry and say so
        for ($i = 0; $i -lt 5; $i++) {
            [gc]::Collect(); Start-Sleep -Seconds 2
            cmd /c "reg unload HKLM\Settings >nul 2>&1"
            if ($LASTEXITCODE -eq 0) { break }
        }
        if ($LASTEXITCODE -ne 0) { Write-Host "  ${Name}: settings file still loaded; restart Windows before using this app." -ForegroundColor Yellow }
    }
    else { Write-Host "  ${Name}: settings file is in use, skipped (close the app and run Tweaks again)." -ForegroundColor Yellow }
}

# only the Game Bar overlay goes; the Xbox app and Gaming Services (Game Pass games) stay. -Apps xbox keeps the Game Bar.
if ($Apps -ne 'xbox') {
Write-Host 'Game Bar: off'
Stop-Process -Force -Name GameBar -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers Microsoft.XboxGamingOverlay | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Import-Reg 'gamebaroff' @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\GameDVR]
"AppCaptureEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\GameBar]
"UseNexusForGameBarEnabled"=dword:00000000
"GamepadNexusChordEnabled"=dword:00000000

[HKEY_CLASSES_ROOT\ms-gamebar]
@="URL:ms-gamebar"
"URL Protocol"=""
"NoOpenWith"=""

[HKEY_CLASSES_ROOT\ms-gamebar\shell\open\command]
@="%SystemRoot%\\System32\\systray.exe"

[HKEY_CLASSES_ROOT\ms-gamebarservices]
@="URL:ms-gamebarservices"
"URL Protocol"=""
"NoOpenWith"=""

[HKEY_CLASSES_ROOT\ms-gamebarservices\shell\open\command]
@="%SystemRoot%\\System32\\systray.exe"

[HKEY_CLASSES_ROOT\ms-gamingoverlay]
@="URL:ms-gamingoverlay"
"URL Protocol"=""
"NoOpenWith"=""

[HKEY_CLASSES_ROOT\ms-gamingoverlay\shell\open\command]
@="%SystemRoot%\\System32\\systray.exe"
'@
Run-Trusted "reg add `"HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter`" /v `"ActivationType`" /t REG_DWORD /d `"0`" /f"
}

Write-Host 'Start menu: new layout, list view'
Import-Reg 'newstartmenu' @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\14\2792562829]
"EnabledState"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\14\3036241548]
"EnabledState"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\14\734731404]
"EnabledState"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\14\762256525]
"EnabledState"=dword:00000002

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Start]
"AllAppsViewMode"=dword:00000002
'@

Write-Host 'Edge: performance (kept installed; WebView2 under it draws the Start search box)'
Import-Reg 'edgeperformance' @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge]
; no preloaded Edge at sign-in, nothing left running after the last window closes
"StartupBoostEnabled"=dword:00000000
"BackgroundModeEnabled"=dword:00000000
; idle tabs sleep and free memory and CPU
"SleepingTabsEnabled"=dword:00000001
"EfficiencyModeEnabled"=dword:00000001
; side bar, shopping and suggestion pop-ups off
"HubsSidebarEnabled"=dword:00000000
"EdgeShoppingAssistantEnabled"=dword:00000000
"ShowRecommendationsEnabled"=dword:00000000
"PersonalizationReportingEnabled"=dword:00000000
"HideFirstRunExperience"=dword:00000001
'@
# Edge's own sign-in setup and run-once entries
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components' -ErrorAction SilentlyContinue | ForEach-Object {
    # only the Edge browser component; a name match could also hit WebView2, which Start search needs
    if ($_.PSChildName -eq '{9459C573-B17A-45AE-9F64-1857B5D58CEE}') { Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue }
}
$runOnce = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
(Get-Item $runOnce -ErrorAction SilentlyContinue).Property | Where-Object { $_ -like '*msedge*' } | ForEach-Object { Remove-ItemProperty -Path $runOnce -Name $_ -Force -ErrorAction SilentlyContinue }

Write-Host 'Notepad: settings'
Stop-Process -Name Notepad -Force -ErrorAction SilentlyContinue
Import-AppSettings "$env:LOCALAPPDATA\Packages\Microsoft.WindowsNotepad_8wekyb3d8bbwe\Settings\settings.dat" 'notepadsettings' @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Settings\LocalState]
"OpenFile"=hex(5f5e104):01,00,00,00,d1,55,24,57,d1,84,db,01
"GhostFile"=hex(5f5e10b):00,42,60,f1,5a,d1,84,db,01
"RewriteEnabled"=hex(5f5e10b):00,12,4a,7f,5f,d1,84,db,01
'@

Write-Host 'Control Panel and Settings: optimize'
Stop-Service -Name camsvc -Force -ErrorAction SilentlyContinue
Run-Trusted "Remove-Item `"$env:ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityConsentStorage.db*`" -Force"
cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Services\CDPUserSvc`" /v `"Start`" /t REG_DWORD /d `"4`" /f >nul 2>&1"
# '?' stands for '$' in the CloudStore key names below; replaced before import
$controlPanel = @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Narrator\NoRoam]
"DuckAudio"=dword:00000000
"WinEnterLaunchEnabled"=dword:00000000
"ScriptingEnabled"=dword:00000000
"OnlineServicesEnabled"=dword:00000000
"EchoToggleKeys"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Narrator]
"NarratorCursorHighlight"=dword:00000000
"CoupleNarratorCursorKeyboard"=dword:00000000
"IntonationPause"=dword:00000000
"ReadHints"=dword:00000000
"ErrorNotificationType"=dword:00000000
"EchoChars"=dword:00000000
"EchoWords"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Narrator\NarratorHome]
"MinimizeType"=dword:00000000
"AutoStart"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Ease of Access]
"selfvoice"=dword:00000000
"selfscan"=dword:00000000

[HKEY_CURRENT_USER\Control Panel\Accessibility]
"Sound on Activation"=dword:00000000
"Warning Sounds"=dword:00000000

[HKEY_CURRENT_USER\Control Panel\Accessibility\HighContrast]
"Flags"="4194"

[HKEY_CURRENT_USER\Control Panel\Accessibility\Keyboard Response]
"Flags"="2"
"AutoRepeatRate"="0"
"AutoRepeatDelay"="0"

[HKEY_CURRENT_USER\Control Panel\Accessibility\MouseKeys]
"Flags"="130"
"MaximumSpeed"="39"
"TimeToMaximumSpeed"="3000"

[HKEY_CURRENT_USER\Control Panel\Accessibility\StickyKeys]
"Flags"="2"

[HKEY_CURRENT_USER\Control Panel\Accessibility\ToggleKeys]
"Flags"="34"

[HKEY_CURRENT_USER\Control Panel\Accessibility\SoundSentry]
"Flags"="0"
"FSTextEffect"="0"
"TextEffect"="0"
"WindowsEffect"="0"

[HKEY_CURRENT_USER\Control Panel\Accessibility\SlateLaunch]
"ATapp"=""
"LaunchAT"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\ScreenMagnifier]
"FollowCaret"=dword:00000000
"FollowNarrator"=dword:00000000
"FollowMouse"=dword:00000000
"FollowFocus"=dword:00000000

[HKEY_CURRENT_USER\Control Panel\TimeDate]
"DstNotification"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"LaunchTo"=dword:00000001
"HideFileExt"=dword:00000000
"FolderContentsInfoTip"=dword:00000000
"ShowInfoTip"=dword:00000000
"ShowPreviewHandlers"=dword:00000000
"ShowStatusBar"=dword:00000000
"ShowSyncProviderNotifications"=dword:00000000
"SharingWizardOn"=dword:00000000
"TaskbarAnimations"=dword:00000000
"IconsOnly"=dword:00000000
"ListviewAlphaSelect"=dword:00000000
"ListviewShadow"=dword:00000000
"Start_Layout"=dword:00000001
"Start_AccountNotifications"=dword:00000000
"Start_RecoPersonalizedSites"=dword:00000000
"Start_TrackDocs"=dword:00000000
"IconSizePreference"=dword:00000001
"TaskbarAl"=dword:00000000
"TaskbarSd"=dword:00000001
"TaskbarMn"=dword:00000000
"ShowTaskViewButton"=dword:00000000
"ShowCopilotButton"=dword:00000000
"IsEnabled"=dword:00000000
"Start_IrisRecommendations"=dword:00000000
"TaskbarSn"=dword:00000000
"SnapAssist"=dword:00000000
"DITest"=dword:00000000
"EnableSnapBar"=dword:00000000
"EnableTaskGroups"=dword:00000000
"EnableSnapAssistFlyout"=dword:00000000
"SnapFill"=dword:00000000
"JointResize"=dword:00000000
"MultiTaskingAltTabFilter"=dword:00000003

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer]
"ShowFrequent"=dword:00000000
"ShowCloudFilesInQuickAccess"=dword:00000000
"EnableAutoTray"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\SearchSettings]
"IsDeviceSearchHistoryEnabled"=dword:00000000
"IsDynamicSearchBoxEnabled"=dword:00000000
"SafeSearchMode"=dword:00000000
"IsAADCloudSearchEnabled"=dword:00000000
"IsMSACloudSearchEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState]
"FullPath"=dword:00000001

[HKEY_CURRENT_USER\Software\Classes\CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}]
"System.IsPinnedToNameSpaceTree"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings]
"ShowLockOption"=dword:00000000
"ShowSleepOption"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Multimedia\Audio]
"UserDuckingPreference"=dword:00000003

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation]
"DisableStartupSound"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\EditionOverrides]
"UserSetting_DisableStartupSound"=dword:00000001

[HKEY_CURRENT_USER\AppEvents\Schemes]
@=".None"

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\.Default\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\CriticalBatteryAlarm\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\DeviceConnect\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\DeviceDisconnect\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\DeviceFail\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\FaxBeep\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\LowBatteryAlarm\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\MailBeep\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\MessageNudge\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.Default\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.IM\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.Mail\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.Proximity\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.Reminder\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\Notification.SMS\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\ProximityConnection\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\SystemAsterisk\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\SystemExclamation\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\SystemHand\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\SystemNotification\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\WindowsUAC\.Current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\DisNumbersSound\.current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\HubOffSound\.current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\HubOnSound\.current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\HubSleepSound\.current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\MisrecoSound\.current]
@=""

[HKEY_CURRENT_USER\AppEvents\Schemes\Apps\sapisvr\PanelSound\.current]
@=""

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers]
"DisableAutoplay"=dword:00000001

[HKEY_CURRENT_USER\Control Panel\Mouse]
"MouseSpeed"="0"
"MouseThreshold1"="0"
"MouseThreshold2"="0"
"MouseSensitivity"="10"
"SmoothMouseXCurve"=hex:00,00,00,00,00,00,00,00,C0,CC,0C,00,00,00,00,00,80,99,19,00,00,00,00,00,40,66,26,00,00,00,00,00,00,33,33,00,00,00,00,00
"SmoothMouseYCurve"=hex:00,00,00,00,00,00,00,00,00,00,38,00,00,00,00,00,00,00,70,00,00,00,00,00,00,00,A8,00,00,00,00,00,00,00,E0,00,00,00,00,00

[HKEY_USERS\.DEFAULT\Control Panel\Mouse]
"MouseSpeed"="0"
"MouseThreshold1"="0"
"MouseThreshold2"="0"

[HKEY_CURRENT_USER\Control Panel\Cursors]
"AppStarting"=hex(2):00,00
"Arrow"=hex(2):00,00
"ContactVisualization"=dword:00000000
"Crosshair"=hex(2):00,00
"GestureVisualization"=dword:00000000
"Hand"=hex(2):00,00
"Help"=hex(2):00,00
"IBeam"=hex(2):00,00
"No"=hex(2):00,00
"NWPen"=hex(2):00,00
"Scheme Source"=dword:00000000
"SizeAll"=hex(2):00,00
"SizeNESW"=hex(2):00,00
"SizeNS"=hex(2):00,00
"SizeNWSE"=hex(2):00,00
"SizeWE"=hex(2):00,00
"UpArrow"=hex(2):00,00
"Wait"=hex(2):00,00
@=""

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata]
"PreventDeviceMetadataFromNetwork"=dword:00000001

[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\Network\SharedAccessConnection]
"EnableControl"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Dfrg\TaskSettings]
"fAllVolumes"=dword:00000001
"fDeadlineEnabled"=dword:00000000
"fExclude"=dword:00000000
"fTaskEnabled"=dword:00000000
"fUpgradeRestored"=dword:00000001
"TaskFrequency"=dword:00000004
"Volumes"=" "

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects]
"VisualFXSetting"=dword:00000003

[HKEY_CURRENT_USER\Control Panel\Desktop]
"UserPreferencesMask"=hex:90,12,03,80,12,00,00,00
"DragFullWindows"="0"
"FontSmoothing"="2"
"MenuShowDelay"="0"
"LogPixels"=dword:00000060
"Win8DpiScaling"=dword:00000001
"EnablePerProcessSystemDPI"=dword:00000000

[HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics]
"MinAnimate"="0"

[HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM]
"EnableAeroPeek"=dword:00000000
"AlwaysHibernateThumbnails"=dword:00000000
"UseDpiScaling"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl]
"Win32PrioritySeparation"=dword:00000026

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Remote Assistance]
"fAllowToGetHelp"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance]
"MaintenanceDisabled"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting]
"Disabled"=dword:00000001

[HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings]
"DownloadMode"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\MdmCommon\SettingValues]
"LocationSyncEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications]
"EnableAccountNotifications"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\TailoredExperiencesWithDiagnosticDataEnabled]
"Value"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Privacy]
"TailoredExperiencesWithDiagnosticDataEnabled"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location]
"Value"="Deny"

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting]
"Value"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location]
"ShowGlobalPrompts"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam]
"Value"="Allow"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone]
"Value"="Allow"

[HKEY_CURRENT_USER\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps]
"AgentActivationEnabled"=dword:00000000
"AgentActivationLastUsed"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userNotificationListener]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userAccountInformation]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\contacts]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appointments]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\phoneCall]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\phoneCallHistory]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\email]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userDataTasks]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\chat]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\radios]
"Value"="Deny"

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\bluetoothSync]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\documentsLibrary]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\downloadsFolder]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\musicLibrary]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\picturesLibrary]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\videosLibrary]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\broadFileSystemAccess]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\passkeys]
"Value"="Deny"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\passkeysEnumeration]
"Value"="Deny"

[HKEY_CURRENT_USER\Control Panel\International\User Profile]
"HttpAcceptLanguageOptOut"=dword:00000001

[HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\EdgeUI]
"DisableMFUTracking"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\EdgeUI]
"DisableMFUTracking"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\InputPersonalization]
"RestrictImplicitInkCollection"=dword:00000001
"RestrictImplicitTextCollection"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\InputPersonalization\TrainedDataStore]
"HarvestContacts"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Personalization\Settings]
"AcceptedPrivacyPolicy"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\DataCollection]
"AllowTelemetry"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Siuf\Rules]
"NumberOfSIUFInPeriod"=dword:00000000
"PeriodInNanoSeconds"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"PublishUserActivities"=dword:00000000
"DisableAcrylicBackgroundOnLogon"=dword:00000001

[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\GameBar]
"UseNexusForGameBarEnabled"=dword:00000000
"GamepadNexusChordEnabled"=dword:00000000
"AutoGameModeEnabled"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\GameDVR]
"AppCaptureEnabled"=dword:00000000
"AudioEncodingBitrate"=dword:0001f400
"AudioCaptureEnabled"=dword:00000000
"CustomVideoEncodingBitrate"=dword:003d0900
"CustomVideoEncodingHeight"=dword:000002d0
"CustomVideoEncodingWidth"=dword:00000500
"HistoricalBufferLength"=dword:0000001e
"HistoricalBufferLengthUnit"=dword:00000001
"HistoricalCaptureEnabled"=dword:00000000
"HistoricalCaptureOnBatteryAllowed"=dword:00000001
"HistoricalCaptureOnWirelessDisplayAllowed"=dword:00000001
"MaximumRecordLength"=hex(b):00,D0,88,C3,10,00,00,00
"VideoEncodingBitrateMode"=dword:00000002
"VideoEncodingResolutionMode"=dword:00000002
"VideoEncodingFrameRateMode"=dword:00000000
"EchoCancellationEnabled"=dword:00000001
"CursorCaptureEnabled"=dword:00000000
"VKToggleGameBar"=dword:00000000
"VKMToggleGameBar"=dword:00000000
"VKSaveHistoricalVideo"=dword:00000000
"VKMSaveHistoricalVideo"=dword:00000000
"VKToggleRecording"=dword:00000000
"VKMToggleRecording"=dword:00000000
"VKTakeScreenshot"=dword:00000000
"VKMTakeScreenshot"=dword:00000000
"VKToggleRecordingIndicator"=dword:00000000
"VKMToggleRecordingIndicator"=dword:00000000
"VKToggleMicrophoneCapture"=dword:00000000
"VKMToggleMicrophoneCapture"=dword:00000000
"VKToggleCameraCapture"=dword:00000000
"VKMToggleCameraCapture"=dword:00000000
"VKToggleBroadcast"=dword:00000000
"VKMToggleBroadcast"=dword:00000000
"MicrophoneCaptureEnabled"=dword:00000000
"SystemAudioGain"=hex(b):10,27,00,00,00,00,00,00
"MicrophoneGain"=hex(b):10,27,00,00,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\input\Settings]
"IsVoiceTypingKeyEnabled"=dword:00000000
"InsightsEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\TabletTip\1.7]
"EnableAutoShiftEngage"=dword:00000000
"EnableKeyAudioFeedback"=dword:00000000
"EnableDoubleTapSpace"=dword:00000000
"TouchKeyboardTapInvoke"=dword:00000000
"TipbandDesiredVisibility"=dword:00000000
"IsKeyBackgroundEnabled"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\CTF\LangBar]
"ExtraIconsOnMinimized"=dword:00000000
"Label"=dword:00000000
"ShowStatus"=dword:00000003
"Transparency"=dword:000000ff

[HKEY_CURRENT_USER\Keyboard Layout\Toggle]
"Language Hotkey"="3"
"Hotkey"="3"
"Layout Hotkey"="3"

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search]
"GleamEnabled"=dword:00000000
"WeatherEnabled"=dword:00000000
"HolidayEnabled"=dword:00000000
"SearchboxTaskbarMode"=dword:00000000
"BackgroundAppGlobalToggle"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Winlogon]
"EnableGoodbye"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System]
"DisableAutomaticRestartSignOn"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device]
"DevicePasswordLessBuildVersion"=dword:00000000
"DevicePasswordLessUpdateType"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\SettingSync]
"DisableAccessibilitySettingSync"=dword:00000002
"DisableAccessibilitySettingSyncUserOverride"=dword:00000001
"DisableAppSyncSettingSync"=dword:00000002
"DisableAppSyncSettingSyncUserOverride"=dword:00000001
"DisableApplicationSettingSync"=dword:00000002
"DisableApplicationSettingSyncUserOverride"=dword:00000001
"DisableCredentialsSettingSync"=dword:00000002
"DisableCredentialsSettingSyncUserOverride"=dword:00000001
"DisableDesktopThemeSettingSync"=dword:00000002
"DisableDesktopThemeSettingSyncUserOverride"=dword:00000001
"DisableLanguageSettingSync"=dword:00000002
"DisableLanguageSettingSyncUserOverride"=dword:00000001
"DisablePersonalizationSettingSync"=dword:00000002
"DisablePersonalizationSettingSyncUserOverride"=dword:00000001
"DisableSettingSync"=dword:00000002
"DisableSettingSyncUserOverride"=dword:00000001
"DisableStartLayoutSettingSync"=dword:00000002
"DisableStartLayoutSettingSyncUserOverride"=dword:00000001
"DisableSyncOnPaidNetwork"=dword:00000001
"DisableWebBrowserSettingSync"=dword:00000002
"DisableWebBrowserSettingSyncUserOverride"=dword:00000001
"DisableWindowsSettingSync"=dword:00000002
"DisableWindowsSettingSyncUserOverride"=dword:00000001
"EnableWindowsBackup"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\Maps]
"AutoUpdateEnabled"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Appx]
"AllowAutomaticAppArchiving"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu]
"{645FF040-5081-101B-9F08-00AA002F954E}"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel]
"{645FF040-5081-101B-9F08-00AA002F954E}"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer]
"ShowOrHideMostUsedApps"=dword:00000002
"HideRecommendedSection"=dword:00000001
"HideRecentlyAddedApps"=dword:00000001

[HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer]
"ShowOrHideMostUsedApps"=-

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer]
"NoStartMenuMFUprogramsList"=-
"NoInstrumentation"=-
"HideSCAMeetNow"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]
"NoStartMenuMFUprogramsList"=-
"NoInstrumentation"=-
"HideRecentlyAddedApps"=dword:00000001
"NoWebServices"=dword:00000001
"SettingsPageVisibility"="hide:home;"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\Start]
"HideRecommendedSection"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\Education]
"IsEducationEnvironment"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh]
"AllowNewsAndInterests"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds]
"EnableFeeds"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run]
"SecurityHealth"=hex(3):07,00,00,00,05,DB,8A,69,8A,49,D9,01

[HKEY_CURRENT_USER\Software\Microsoft\Lighting]
"AmbientLightingEnabled"=dword:00000000
"ControlledByForegroundApp"=dword:00000000
"UseSystemAccentColor"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Start]
"ShowRecentList"=dword:00000000
"ShowPinnedSection"=dword:00000001
"ShowRecentSection"=dword:00000000
"ShowSuggestedFiles"=dword:00000000
"ShowAllAppsSection"=dword:00000001
"ShowFrequentList"=dword:00000000
"StartMenuSize"=dword:00000001
"HideUserInformation"=dword:00000000
"RightCompanionToggledOpen"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Start\Companions\Microsoft.YourPhone_8wekyb3d8bbwe]
"IsEnabled"=dword:00000000
"IsAvailable"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\developer]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\gaming]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\family]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\creative]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\schoolwork]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\entertainment]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\business]
"Intent"=dword:00000000
"Priority"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Shell\USB]
"NotifyOnUsbErrors"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Windows]
"LegacyDefaultPrinterMode"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\TabletTip\EmbeddedInkControl]
"EnableInkingWithTouch"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers]
"HwSchMode"=dword:00000002

[HKEY_CURRENT_USER\Software\Microsoft\DirectX\UserGpuPreferences]
"DirectXUserGlobalSettings"="SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;"

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\PushNotifications]
"ToastEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings]
"NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND"=dword:00000000
"NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK"=dword:00000000
"NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.AutoPlay]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.CapabilityAccess]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupApp]
"Enabled"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement]
"ScoobeSystemSettingEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard]
"Disabled"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\??windows.data.notifications.quiethourssettings\Current]
"Data"=hex(3):02,00,00,00,B4,67,2B,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,14,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,55,00,6E,00,72,00,65,00,73,00,74,00,72,\
00,69,00,63,00,74,00,65,00,64,00,CA,28,D0,14,02,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\?quietmomentfullscreen?windows.data.notifications.quietmoment\Current]
"Data"=hex(3):02,00,00,00,97,1D,2D,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,1E,26,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,41,00,6C,00,61,00,72,00,6D,00,73,00,4F,\
00,6E,00,6C,00,79,00,C2,28,01,CA,50,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\?quietmomentgame?windows.data.notifications.quietmoment\Current]
"Data"=hex(3):02,00,00,00,6C,39,2D,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,1E,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,50,00,72,00,69,00,6F,00,72,00,69,00,74,\
00,79,00,4F,00,6E,00,6C,00,79,00,C2,28,01,CA,50,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\?quietmomentpostoobe?windows.data.notifications.quietmoment\Current]
"Data"=hex(3):02,00,00,00,06,54,2D,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,1E,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,50,00,72,00,69,00,6F,00,72,00,69,00,74,\
00,79,00,4F,00,6E,00,6C,00,79,00,C2,28,01,CA,50,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\?quietmomentpresentation?windows.data.notifications.quietmoment\Current]
"Data"=hex(3):02,00,00,00,83,6E,2D,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,1E,26,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,41,00,6C,00,61,00,72,00,6D,00,73,00,4F,\
00,6E,00,6C,00,79,00,C2,28,01,CA,50,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\?quietmomentscheduled?windows.data.notifications.quietmoment\Current]
"Data"=hex(3):02,00,00,00,2E,8A,2D,68,F0,0B,D8,01,00,00,00,00,43,42,01,00,\
C2,0A,01,D2,1E,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,74,00,2E,\
00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,00,72,00,\
6F,00,66,00,69,00,6C,00,65,00,2E,00,50,00,72,00,69,00,6F,00,72,00,69,00,74,\
00,79,00,4F,00,6E,00,6C,00,79,00,C2,28,01,D1,32,80,E0,AA,8A,99,30,D1,3C,80,\
E0,F6,C5,D5,0E,CA,50,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default?windows.data.donotdisturb.quietmoment?quietmomentlist\windows.data.donotdisturb.quietmoment?quietmomentpresentation]
"Data"=hex(3):43,42,01,00,0A,02,01,00,2A,06,E2,F3,AA,CC,06,2A,2B,0E,5A,43,\
42,01,00,C2,0A,01,D2,1E,26,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,\
74,00,2E,00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,\
00,72,00,6F,00,66,00,69,00,6C,00,65,00,2E,00,41,00,6C,00,61,00,72,00,6D,00,\
73,00,4F,00,6E,00,6C,00,79,00,CA,50,00,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default?windows.data.donotdisturb.quietmoment?quietmomentlist\windows.data.donotdisturb.quietmoment?quietmomentgame]
"Data"=hex(3):43,42,01,00,0A,02,01,00,2A,06,E1,F3,AA,CC,06,2A,2B,0E,5E,43,\
42,01,00,C2,0A,01,D2,1E,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,\
74,00,2E,00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,\
00,72,00,6F,00,66,00,69,00,6C,00,65,00,2E,00,50,00,72,00,69,00,6F,00,72,00,\
69,00,74,00,79,00,4F,00,6E,00,6C,00,79,00,CA,50,00,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default?windows.data.donotdisturb.quietmoment?quietmomentlist\windows.data.donotdisturb.quietmoment?quietmomentfullscreen]
"Data"=hex(3):43,42,01,00,0A,02,01,00,2A,06,E0,F3,AA,CC,06,2A,2B,0E,5A,43,\
42,01,00,C2,0A,01,D2,1E,26,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,\
74,00,2E,00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,\
00,72,00,6F,00,66,00,69,00,6C,00,65,00,2E,00,41,00,6C,00,61,00,72,00,6D,00,\
73,00,4F,00,6E,00,6C,00,79,00,CA,50,00,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default?windows.data.donotdisturb.quietmoment?quietmomentlist\windows.data.donotdisturb.quietmoment?quietmomentpostoobe]
"Data"=hex(3):43,42,01,00,0A,02,01,00,2A,06,DF,F3,AA,CC,06,2A,2B,0E,5E,43,\
42,01,00,C2,0A,01,D2,1E,28,4D,00,69,00,63,00,72,00,6F,00,73,00,6F,00,66,00,\
74,00,2E,00,51,00,75,00,69,00,65,00,74,00,48,00,6F,00,75,00,72,00,73,00,50,\
00,72,00,6F,00,66,00,69,00,6C,00,65,00,2E,00,50,00,72,00,69,00,6F,00,72,00,\
69,00,74,00,79,00,4F,00,6E,00,6C,00,79,00,CA,50,00,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default?windows.data.shell.focussessionactivetheme\windows.data.shell.focussessionactivetheme?{1b019365-25a5-4ff1-b50a-c155229afc8f}]
"Data"=hex(3):43,42,01,00,0A,00,2A,06,F4,E2,AA,CC,06,2A,2B,0E,08,43,42,01,\
00,C2,0A,01,00,00,00,00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\VideoSettings]
"VideoQualityOnBattery"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\StorageSense]
"AllowStorageSenseGlobal"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy]
"04"=dword:00000000
"2048"=dword:00000000
"08"=dword:00000000
"256"=dword:00000000
"32"=dword:00000000
"StoragePoliciesChanged"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CDP]
"DragTrayEnabled"=dword:00000000
"RomeSdkChannelUserAuthzPolicy"=dword:00000000
"CdpSessionUserAuthzPolicy"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings]
"TaskbarEndTask"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem]
"LongPathsEnabled"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsMitigation]
"UserPreference"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate]
"AutoDownload"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy]
"LetAppsRunInBackground"=dword:00000002

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications]
"GlobalUserDisabled"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Dsh]
"IsPrelaunchEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer]
"DisableSearchBoxSuggestions"=dword:00000001

[HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\WindowsCopilot]
"TurnOffWindowsCopilot"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot]
"TurnOffWindowsCopilot"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsAI]
"DisableAIDataAnalysis"=dword:00000001
"AllowRecallEnablement"=dword:00000000
"DisableClickToDo"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\Shell\Copilot\BingChat]
"IsUserEligible"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint]
"DisableGenerativeFill"=dword:00000001
"DisableCocreator"=dword:00000001
"DisableImageCreator"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\WindowsNotepad]
"DisableAIFeatures"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests]
"value"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager]
"ContentDeliveryAllowed"=dword:00000000
"FeatureManagementEnabled"=dword:00000000
"OemPreInstalledAppsEnabled"=dword:00000000
"PreInstalledAppsEnabled"=dword:00000000
"PreInstalledAppsEverEnabled"=dword:00000000
"RotatingLockScreenEnabled"=dword:00000000
"RotatingLockScreenOverlayEnabled"=dword:00000000
"SilentInstalledAppsEnabled"=dword:00000000
"SlideshowEnabled"=dword:00000000
"SoftLandingEnabled"=dword:00000000
"SubscribedContent-310093Enabled"=dword:00000000
"SubscribedContent-314563Enabled"=dword:00000000
"SubscribedContent-338388Enabled"=dword:00000000
"SubscribedContent-338389Enabled"=dword:00000000
"SubscribedContent-338393Enabled"=dword:00000000
"SubscribedContent-353694Enabled"=dword:00000000
"SubscribedContent-353696Enabled"=dword:00000000
"SubscribedContent-353698Enabled"=dword:00000000
"SubscribedContentEnabled"=dword:00000000
"SystemPaneSuggestionsEnabled"=dword:00000000

[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}]

[-HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer]
"HubMode"=dword:00000001

[HKEY_CURRENT_USER\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}]
"System.IsPinnedToNameSpaceTree"=dword:00000000

[HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32]
@=""

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching]
"SearchOrderConfig"=dword:00000000

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\CrashControl]
"DisplayParameters"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager]
"DisableWpbtExecution"=dword:00000001

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration]
"IsResumeAllowed"=dword:00000000
"IsOneDriveResumeAllowed"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Connectivity\DisableCrossDeviceResume]
"value"=dword:00000001

; phone-PC linking off (Phone Link, Resume)
[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"EnableMmx"=dword:00000000

; CrossDeviceResume.exe is part of the Start/shell package and cannot be removed: start a no-op stub instead of it
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\CrossDeviceResume.exe]
"Debugger"="C:\\Windows\\System32\\systray.exe"

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1387020943]
"EnabledState"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260]
"EnabledState"=dword:00000001

[HKEY_CURRENT_USER\Console\%%Startup]
"DelegationConsole"="{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"
"DelegationTerminal"="{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"

[HKEY_CURRENT_USER\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe]
"ScreenColors"=dword:0000000F
'@
# -Apps store / xbox: keep Store auto-update and background apps (Store and Xbox downloads, sign-in)
if ($Apps -ne 'off') {
    foreach ($key in 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate',
                     'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy',
                     'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications') {
        $controlPanel = Remove-RegKeyBlock $controlPanel $key
    }
}
Import-Reg 'controlpanel' $controlPanel.Replace('?', '$')
Stop-Service -Name camsvc -Force -ErrorAction SilentlyContinue
Run-Trusted "Remove-Item `"$env:ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityConsentStorage.db*`" -Force"
Get-ScheduledTask | Where-Object { $_.TaskName -match 'ScheduledDefrag' } | Disable-ScheduledTask | Out-Null
powercfg /setdcvalueindex scheme_current sub_none consolelock 0 2>$null
powercfg /setacvalueindex scheme_current sub_none consolelock 0 2>$null
powercfg /setactive scheme_current 2>$null
# app actions off for Paint and Photos (the Start/search component is left alone)
'AppActions', 'DesktopStickerEditorWin32Exe', 'DiscoveryHubApp', 'VisualAssistExe', 'CrossDeviceResume' | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
Import-AppSettings "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\Settings\settings.dat" 'appactions' @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Settings\LocalState\DisabledApps]
"Microsoft.Paint_8wekyb3d8bbwe"=hex(5f5e10b):01,61,ed,11,34,f7,9f,dc,01
"Microsoft.Windows.Photos_8wekyb3d8bbwe"=hex(5f5e10b):01,61,ed,11,34,f7,9f,dc,01
'@

Write-Host 'Sound: Enhancements tab on every playback device'
Stop-Service audiosrv -Force -ErrorAction SilentlyContinue
Stop-Service AudioEndpointBuilder -Force -ErrorAction SilentlyContinue
$fx = "Windows Registry Editor Version 5.00`r`n"
foreach ($g in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render' -ErrorAction SilentlyContinue) {
    $fx += "`r`n[$($g.Name)\FxProperties]`r`n`"{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},3`"=`"{5860E1C5-F95C-4a7a-8EC8-8AEF24F379A1}`"`r`n"
}
Import-Reg 'enhancements' $fx
Start-Service AudioEndpointBuilder -ErrorAction SilentlyContinue
Start-Service audiosrv -ErrorAction SilentlyContinue

Write-Host 'Devices: power saving and wake off'
foreach ($bus in 'ACPI', 'HID', 'PCI', 'USB') {
    # Ignore, not SilentlyContinue: the locked Properties subkeys would otherwise fill $Error and push real errors out
    foreach ($key in Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\$bus" -Recurse -ErrorAction Ignore) {
        $path = $key.Name
        if ($key.PSChildName -eq 'Device Parameters') {
            cmd /c "reg add `"$path`" /v `"EnhancedPowerManagementEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
            cmd /c "reg add `"$path`" /v `"SelectiveSuspendEnabled`" /t REG_BINARY /d `"00`" /f >nul 2>&1"
            cmd /c "reg add `"$path`" /v `"SelectiveSuspendOn`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
            cmd /c "reg add `"$path`" /v `"WaitWakeEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
        }
        elseif ($key.PSChildName -eq 'WDF') {
            cmd /c "reg add `"$path`" /v `"IdleInWorkingState`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
        }
    }
}
Write-Host 'Network adapters: power saving and wake off'
foreach ($key in Get-ChildItem 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }) {
    $path = $key.Name
    cmd /c "reg add `"$path`" /v `"PnPCapabilities`" /t REG_DWORD /d `"24`" /f >nul 2>&1"
    foreach ($v in 'AdvancedEEE', '*EEE', 'EEELinkAdvertisement', 'SipsEnabled', 'ULPMode', 'GigaLite', 'EnableGreenEthernet', 'PowerSavingMode',
                   'S5WakeOnLan', '*WakeOnMagicPacket', '*ModernStandbyWoLMagicPacket', '*WakeOnPattern', 'WakeOnLink') {
        cmd /c "reg add `"$path`" /v `"$v`" /t REG_SZ /d `"0`" /f >nul 2>&1"
    }
}

Write-Host 'Network: IPv4 only'
# -Apps xbox keeps IPv6 (ms_tcpip6): Teredo carries Xbox party chat and multiplayer
foreach ($binding in (@('ms_lldp', 'ms_lltdio', 'ms_implat', 'ms_rspndr') + @(if ($Apps -ne 'xbox') { 'ms_tcpip6' }) + @('ms_server', 'ms_msclient', 'ms_pacer'))) {
    Disable-NetAdapterBinding -Name '*' -ComponentID $binding -ErrorAction SilentlyContinue
}

Write-Host 'Disks: write-cache buffer flushing off'
foreach ($bus in 'SCSI', 'NVME') {
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\$bus" -Recurse -ErrorAction Ignore | Where-Object { $_.PSChildName -eq 'Device Parameters' } | ForEach-Object {
        cmd /c "reg add `"$($_.Name)\Disk`" /v `"CacheIsPowerProtected`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
    }
}

# the desktop keeps its wallpaper; no solid black background
Write-Host 'Theme: black'
Import-Reg 'blacktheme' @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize]
"AppsUseLightTheme"=dword:00000000
"ColorPrevalence"=dword:00000001
"EnableTransparency"=dword:00000000
"SystemUsesLightTheme"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize]
"AppsUseLightTheme"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent]
"AccentPalette"=hex:64,64,64,00,6b,6b,6b,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00
"StartColorMenu"=dword:00000000
"AccentColorMenu"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM]
"EnableWindowColorization"=dword:00000001
"AccentColor"=dword:ff191919
"ColorizationColor"=dword:c4191919
"ColorizationAfterglow"=dword:c4191919
'@

Write-Host "Done.`n"
if ($Apps -ne 'off') {
    Write-Host 'Store/Xbox: Windows Update gets the monthly update only (no new Windows version, drivers or previews)'
    Set-AppsUpdatePolicy
    # undo what an earlier default run set, so a PC that was already set up works too
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -ErrorAction SilentlyContinue
    Set-Reg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 0
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate' -Name 'AutoDownload' -ErrorAction SilentlyContinue
}
if ($Apps -eq 'xbox') {
    Write-Host 'Xbox: IPv6 (Teredo) and the Game Bar back on'
    Enable-NetAdapterBinding -Name '*' -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
    # the default run pointed these Game Bar links at systray.exe; without the override the Game Bar app handles them
    foreach ($protocol in 'ms-gamebar', 'ms-gamebarservices', 'ms-gamingoverlay') {
        Remove-Item -Path "HKLM:\SOFTWARE\Classes\$protocol" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Run-Trusted "reg add `"HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter`" /v `"ActivationType`" /t REG_DWORD /d `"1`" /f"
}

# non-zero when a critical step failed (TrustedInstaller path not restored), so the Launcher shows it
if ($global:CullewieTrustedBroken -or $global:CullewieTrustedFailed) { exit 1 }
exit 0
