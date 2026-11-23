# Vanilla: undoes this toolkit's Windows changes and goes back to Windows 11 defaults. GPU drivers and GPU settings stay.
#  - services: every service Services.ps1 touches gets its Windows 11 default start type; keys an earlier run created for
#    services that do not exist on this PC (only a "Start" value) are removed
#  - network: IPv6, file sharing (SMB), QoS and network discovery bindings back on, Teredo default, IPv4 preference off
#  - policies: every policy value Tweaks.ps1, Defender.ps1 or the Store/Xbox option writes is removed (exported first)
#  - Defender: SmartScreen, cloud protection, Smart App Control state values removed (Windows defaults), scheduled scans on
#  - power plans restored, Timer Resolution service removed, System Restore on, Store auto-update and background apps on
#  - Microsoft Store and Xbox apps installed (Store-Xbox.ps1 -Apps xbox)
#  - the user's own look (theme, colours, visual effects, scaling, taskbar, Start menu, Explorer, context menu) from the
#    copy Tweaks.ps1 saved before it changed them; without that copy the look stays as it is
#  - removed apps, Windows features and programs (OneDrive, GameInput) reinstalled from the list Tweaks.ps1 saved;
#    apps no longer offered anywhere are listed, not forced
# Not undone: BitLocker (turn it on yourself), apps that are no longer offered, Remote Desktop Connection.
# -PlanOnly: write what would change to -PlanPath and stop; nothing is changed. Restart Windows afterwards.
# -AppsOnly: run by a one-time logon task after the restart: Store / Xbox apps and the removed apps only.
param([switch]$PlanOnly, [string]$PlanPath = "$env:ProgramData\Cullewie\Work\vanilla-plan.txt", [switch]$AppsOnly)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$work = Join-Path $env:ProgramData 'Cullewie\Work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$log = Join-Path $work ('vanilla-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
function Write-Log([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color; if (-not $PlanOnly) { Add-Content -Path $log -Value $Text -Encoding UTF8 } }

# ---------- Windows 11 default start types ----------
# Measured, not guessed: read on Windows 11 build 26300 right after Settings > Recovery > "Fix problems using Windows
# Update" reinstalled Windows. 2 = automatic (some of them delayed), 4 = disabled by default; every other service the
# toolkit touches is 3 (manual / on demand) there. Services that no longer exist in this build are skipped.
$autoStart = @('AppXSvc', 'AudioEndpointBuilder', 'Audiosrv', 'BITS', 'BrokerInfrastructure', 'camsvc', 'cbdhsvc', 'CDPSvc',
    'CDPUserSvc', 'CoreMessagingRegistrar', 'CryptSvc', 'DcomLaunch', 'Dhcp', 'DiagTrack', 'DispBrokerDesktopSvc', 'Dnscache',
    'DPS', 'DusmSvc', 'edgeupdate', 'EventLog', 'gpsvc', 'InventorySvc', 'iphlpsvc', 'LanmanServer', 'LSM', 'MapsBroker', 'nsi',
    'PcaSvc', 'Power', 'ProfSvc', 'RpcEptMapper', 'RpcSs', 'Schedule', 'SENS', 'ShellHWDetection', 'Spooler', 'sppsvc', 'StateRepository',
    'SysMain', 'SystemEventsBroker', 'TextInputManagementService', 'TrkWks', 'UserManager', 'UsoSvc', 'whesvc', 'Winmgmt',
    'WlanSvc', 'WpnService', 'WpnUserService', 'WSAIFabricSvc', 'WSearch')
# PcaSvc: right after the reinstall it was manual, minutes later Windows itself set it to delayed automatic (its state before too)
$delayedStart = @('BITS', 'cbdhsvc', 'CDPSvc', 'edgeupdate', 'InventorySvc', 'MapsBroker', 'PcaSvc', 'sppsvc', 'UsoSvc', 'whesvc', 'WSearch')
$disabledByDefault = @('AppVClient', 'DialogBlockingService', 'MsKeyboardFilter', 'NetTcpPortSharing', 'RemoteAccess',
    'RemoteRegistry', 'shpamsvc', 'ssh-agent', 'tzautoupdate', 'UevAgentService')
function Get-DefaultStart([string]$Name) {
    if ($autoStart -contains $Name) { return 2 }
    if ($disabledByDefault -contains $Name) { return 4 }
    3
}
# the services Services.ps1 changes, read from its list (so a new entry there is covered here too)
$servicesText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Services.ps1'))
$names = @([regex]::Matches($servicesText, '(?m)^\[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\([^\]]+)\]\r?\n"Start"=') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
# plus what the Store/Xbox step switches through the service manager, and the Edge services Tweaks.ps1 disables
$names += 'xboxgip', 'xinputhid', 'edgeupdate', 'edgeupdatem', 'MicrosoftEdgeElevationService'

$serviceRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$plan = New-Object System.Collections.Generic.List[object]
$stubs = New-Object System.Collections.Generic.List[string]
$allKeys = @(Get-ChildItem $serviceRoot -ErrorAction SilentlyContinue)
foreach ($name in $names) {
    # the service itself and its per-user copies (CDPUserSvc_1a2b3 ...)
    $targets = @($allKeys | Where-Object { $_.PSChildName -eq $name -or $_.PSChildName -match ('^' + [regex]::Escape($name) + '_[0-9a-f]{4,}$') })
    foreach ($key in $targets) {
        # a key with nothing but "Start" was created by an earlier reg import for a service this PC does not have
        if ($key.ValueCount -eq 1 -and $key.SubKeyCount -eq 0 -and $key.GetValueNames() -contains 'Start') { $stubs.Add($key.PSChildName); continue }
        $now = $key.GetValue('Start')
        $want = Get-DefaultStart $name
        $wantDelayed = [int]($delayedStart -contains $name)
        $nowDelayed = [int]$key.GetValue('DelayedAutostart')
        # per-user copies (cbdhsvc_1a2b3) never get the delayed flag from Windows, so only the service itself is checked
        $checkDelayed = $want -eq 2 -and $key.PSChildName -eq $name
        if ($now -ne $want -or ($checkDelayed -and $nowDelayed -ne $wantDelayed)) {
            $plan.Add([pscustomobject]@{ Name = $key.PSChildName; From = $now; To = $want; Delayed = $wantDelayed })
        }
    }
}

# ---------- policy values this toolkit writes ----------
# read from the scripts themselves: Set-Reg calls, reg add lines and .reg blocks under ...\Policies\...
function Get-ToolkitPolicyValues([string[]]$Files) {
    $found = @{}
    $add = { param($key, $value) $k = ($key -replace '^HKLM:?\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:?\\', 'HKEY_CURRENT_USER\'); if ($k -match '\\Policies\\') { $found["$k|$value"] = [pscustomobject]@{ Key = $k; Value = $value } } }
    foreach ($file in $Files) {
        $text = [IO.File]::ReadAllText($file)
        foreach ($m in [regex]::Matches($text, 'Set-Reg -Path "(HK[^"]+)" -Name "([^"]+)"')) { & $add $m.Groups[1].Value $m.Groups[2].Value }
        foreach ($m in [regex]::Matches($text, 'reg add `?"(HK[^"`]+)`?" /v `?"([^"`]+)`?"')) { & $add $m.Groups[1].Value $m.Groups[2].Value }
        $current = $null
        foreach ($line in $text -split "`r?`n") {
            if ($line -match '^\[(HKEY_[^\]]+)\]\s*$') { $current = $Matches[1]; continue }
            if ($line -match '^\[') { $current = $null; continue }
            if ($current -and $line -match '^"([^"]+)"=') { & $add $current $Matches[1] }
        }
    }
    @($found.Values)
}
$policyFiles = @('Tweaks.ps1', 'Defender.ps1') | ForEach-Object { Join-Path $PSScriptRoot $_ }
$policies = @(Get-ToolkitPolicyValues $policyFiles)
# Store/Xbox Windows Update policy (written through a variable path, so listed here) and the Launcher's driver block
foreach ($v in 'TargetReleaseVersion', 'ProductVersion', 'TargetReleaseVersionInfo', 'ExcludeWUDriversInQualityUpdate', 'AllowOptionalContent', 'SetAllowOptionalContent') {
    $policies += [pscustomobject]@{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Value = $v }
}
$policies += [pscustomobject]@{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'; Value = 'PreventDeviceMetadataFromNetwork' }
# never delete the values Windows itself keeps under Policies\System (UAC and sign-in): their absence is not the default
$windowsOwned = @('EnableLUA', 'ConsentPromptBehaviorAdmin', 'ConsentPromptBehaviorEnhancedAdmin', 'ConsentPromptBehaviorUser',
    'PromptOnSecureDesktop', 'EnableInstallerDetection', 'EnableSecureUIAPaths', 'EnableVirtualization', 'ValidateAdminCodeSignatures',
    'EnableUIADesktopToggle', 'TypeOfAdminApprovalMode', 'FilterAdministratorToken', 'dontdisplaylastusername', 'shutdownwithoutlogon',
    'undockwithoutlogon', 'scforceoption', 'legalnoticecaption', 'legalnoticetext', 'DSCAutomationHostEnabled', 'EnableCursorSuppression',
    'EnableFullTrustStartupTasks', 'EnableUwpStartupTasks', 'SupportFullTrustStartupTasks', 'SupportUwpStartupTasks')
$policies = @($policies | Where-Object { -not ($_.Key -match '\\CurrentVersion\\Policies\\System$' -and $windowsOwned -contains $_.Value) })
$presentPolicies = @($policies | Where-Object { $null -ne (Get-ItemProperty -Path "Registry::$($_.Key)" -Name $_.Value -ErrorAction SilentlyContinue) })

# ---------- Defender values (not policies; Defender.ps1 writes them as TrustedInstaller) ----------
# Measured on the same reinstalled Windows: every value Defender.ps1 writes is absent there (so it is deleted), except
# these, which exist with a default value (so it is written back). Left alone: Tamper Protection (Windows Security only),
# real-time protection (Defender.ps1 writes 0 = on), DisableAsyncScanOnOpen (Defender.ps1 writes the default, 1), and
# Smart App Control's state values: only a Windows reinstall brings Smart App Control back, and writing them by hand
# could leave it half on.
$defenderDefaults = @{ 'DisableNotifications' = 0 }
$defenderSkip = @('TamperProtection', 'DisableRealtimeMonitoring', 'DisableAsyncScanOnOpen', 'SmartLockerMode',
    'VerifiedAndReputableTrustModeEnabled', 'VerifiedAndReputablePolicyState', 'ENABLED', 'START_PENDING')
$defenderText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Defender.ps1'))
$defenderValues = @([regex]::Matches($defenderText, 'reg add `"(HKEY_[^`]+)`" /v `"([^`]+)`"') | ForEach-Object { [pscustomobject]@{ Key = $_.Groups[1].Value; Value = $_.Groups[2].Value } } |
    # not here: Tamper Protection (Windows Security only), cloud protection and samples (Spynet: set below with
    # Set-MpPreference, Defender guards those values), real-time protection (Defender.ps1 writes 0 = on, the default)
    Where-Object { $_.Key -notmatch '\\Policies\\' -and $_.Key -notmatch '\\Spynet$' -and $_.Value -notin $defenderSkip } | Sort-Object Key, Value -Unique |
    ForEach-Object { $_ | Add-Member -NotePropertyName Default -NotePropertyValue $defenderDefaults[$_.Value] -PassThru } |
    # only what differs from Windows: gone (or at the default value) is the default
    Where-Object { $now = (Get-ItemProperty -Path "Registry::$($_.Key)" -Name $_.Value -ErrorAction SilentlyContinue).($_.Value); $null -ne $now -and ($null -eq $_.Default -or $now -ne $_.Default) })

# ---------- appearance: the user's own look, saved by Tweaks.ps1 before it changed anything ----------
function Open-RegKey([string]$Key, [bool]$Create) {
    $hive = if ($Key -like 'HKEY_LOCAL_MACHINE\*') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $sub = $Key -replace '^HKEY_[A-Z_]+\\', ''
    if ($Create) { $hive.CreateSubKey($sub) } else { $hive.OpenSubKey($sub, $true) }
}
function Get-AppearanceBackup([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    # PowerShell 5.1 hands a JSON array over as one object; ForEach-Object splits it into its entries
    @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | ForEach-Object { $_ })
}
# writes every saved value back as it was (same type), removes values and keys that did not exist before;
# returns how many values differed
function Restore-AppearanceBackup([object[]]$Saved, [switch]$WhatIf) {
    $changed = 0
    foreach ($e in $Saved) {
        $key = Open-RegKey $e.Key $false
        $now = if ($key -and ($key.GetValueNames() -contains $e.Value)) { $key.GetValue($e.Value, $null, 'DoNotExpandEnvironmentNames') } else { $null }
        if ($e.Exists) {
            # plain assignments (a switch or if used as an expression would unroll a byte[] into object[]);
            # the cast is on the value, not the variable, so $data takes another type in the next round
            if ($e.Kind -eq 'Binary') { $data = [byte[]][Convert]::FromBase64String($e.Data) }
            elseif ($e.Kind -eq 'MultiString') { $data = [string[]]@($e.Data) }
            elseif ($e.Kind -eq 'DWord') { $data = [int]$e.Data }
            elseif ($e.Kind -eq 'QWord') { $data = [long]$e.Data }
            else { $data = [string]$e.Data }
            $same = if ($null -eq $now) { $false } elseif ($e.Kind -in 'Binary', 'MultiString') { (@($now) -join ',') -eq (@($data) -join ',') } else { "$now" -eq "$data" }
            if (-not $same) {
                $changed++
                if (-not $WhatIf) { if (-not $key) { $key = Open-RegKey $e.Key $true }; $key.SetValue($e.Value, $data, [Microsoft.Win32.RegistryValueKind]$e.Kind) }
            }
        }
        elseif ($null -ne $now) {
            $changed++
            if (-not $WhatIf) { $key.DeleteValue($e.Value, $false) }
        }
        if ($key) { $key.Close() }
    }
    if (-not $WhatIf) {
        # keys this toolkit created (e.g. the classic context menu key): gone again once empty
        foreach ($e in @($Saved | Where-Object { -not $_.KeyExisted } | Sort-Object { $_.Key.Length } -Descending)) {
            $key = Open-RegKey $e.Key $false
            if ($key -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0) {
                $key.Close()
                $hive = if ($e.Key -like 'HKEY_LOCAL_MACHINE\*') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
                $hive.DeleteSubKey(($e.Key -replace '^HKEY_[A-Z_]+\\', ''), $false)
            }
            elseif ($key) { $key.Close() }
        }
    }
    $changed
}
$appearanceBackup = Join-Path $env:ProgramData ('Cullewie\Work\appearance-backup-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '.json')
$appearanceSaved = Get-AppearanceBackup $appearanceBackup
$appearanceChanges = if ($appearanceSaved.Count) { Restore-AppearanceBackup $appearanceSaved -WhatIf } else { 0 }

# ---------- removed apps and features: the list Tweaks.ps1 saved of what it found and removed ----------
# Store IDs checked with "winget show" (2026-11-23). An app not listed here is no longer offered (Solitaire, Maps, Tips,
# People, Skype, Mail, Cortana, Dev Home, 3D apps, OneNote, Mixed Reality) or has no Store page (Copilot Provider,
# Cross Device): it is listed as not restored, never forced.
$storeIds = [ordered]@{
    'Microsoft.BingNews' = '9WZDNCRFHVFW'; 'Microsoft.BingWeather' = '9WZDNCRFJ3Q2'; 'Microsoft.GetHelp' = '9PKDZBMV1H3T'
    'Microsoft.MicrosoftOfficeHub' = '9WZDNCRD29V9'; 'Microsoft.PowerAutomateDesktop' = '9NFTCH6J7FHV'; 'Microsoft.Todos' = '9NBLGGH5R558'
    'Microsoft.WindowsAlarms' = '9WZDNCRFJ3PR'; 'Microsoft.WindowsFeedbackHub' = '9NBLGGH4R32N'; 'Microsoft.WindowsSoundRecorder' = '9WZDNCRFHWKN'
    'Microsoft.ZuneMusic' = '9WZDNCRFJ3PT'; 'Microsoft.ZuneVideo' = '9WZDNCRFJ3P2'; 'Microsoft.YourPhone' = '9NMPJ99VJBWV'
    'Microsoft.OutlookForWindows' = '9NRX63209R7B'; 'MSTeams' = 'XP8BT8DW290MPQ'; 'Clipchamp.Clipchamp' = '9P1J8S7CCWWT'
    'Microsoft.Copilot' = '9NHT9RB2F4HD'; 'MicrosoftCorporationII.QuickAssist' = '9P7BP5VNWKX5'; 'MicrosoftCorporationII.MicrosoftFamily' = '9PDJDJS743XF'
    'Microsoft.BingSearch' = '9NZBF4GT040C'; 'MicrosoftWindows.Client.WebExperience' = '9MSSGKG348SP'; 'Microsoft.XboxGamingOverlay' = '9NZKPSTSNW4P'
}
# programs from winget; Remote Desktop Connection has no package to reinstall it from
$wingetIds = @{ 'OneDrive' = 'Microsoft.OneDrive'; 'GameInput' = 'Microsoft.GameInput' }
function Get-RemovedInventory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $out = [ordered]@{}
    # each list as a real array, also when it holds one item or none
    foreach ($k in 'apps', 'capabilities', 'features', 'programs') { $out[$k] = @(if ($raw.$k) { $raw.$k | ForEach-Object { [string]$_ } }) }
    [pscustomobject]$out
}
function Get-RestorePlan($Inventory) {
    foreach ($n in @($Inventory.apps)) {
        if ($storeIds.Contains($n)) { [pscustomobject]@{ Kind = 'app'; Name = $n; How = 'msstore'; Id = $storeIds[$n] } }
        else { [pscustomobject]@{ Kind = 'app'; Name = $n; How = 'skip'; Id = '' } }
    }
    foreach ($n in @($Inventory.capabilities)) { [pscustomobject]@{ Kind = 'capability'; Name = $n; How = 'capability'; Id = $n } }
    foreach ($n in @($Inventory.features)) { [pscustomobject]@{ Kind = 'feature'; Name = $n; How = 'feature'; Id = $n } }
    foreach ($n in @($Inventory.programs)) {
        if ($wingetIds.ContainsKey($n)) { [pscustomobject]@{ Kind = 'program'; Name = $n; How = 'winget'; Id = $wingetIds[$n] } }
        else { [pscustomobject]@{ Kind = 'program'; Name = $n; How = 'skip'; Id = '' } }
    }
}
# installs each item (the runner returns $true when it worked); returns what did not come back, with the reason
# one winget run with a time limit: a Store install can wait forever (2026-11-23: the Game Bar, 8+ minutes, twice).
# Its lines are printed when it ends; returns its exit code, -1 when it was stopped.
function Invoke-Winget([string]$Exe, [string[]]$Arguments, [int]$TimeoutSeconds = 900) {
    $out = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $out
    $null = $p.Handle
    $finished = $p.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    # winget's spinner and progress bar lines are left out
    Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Where-Object { $_ -match '[A-Za-z]{2}' } | ForEach-Object { Write-Host $_ }
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    if (-not $finished) { Write-Host "  winget did not finish in $([int]($TimeoutSeconds / 60)) minutes; stopped" -ForegroundColor Yellow; return -1 }
    $p.ExitCode
}
# keeps only the items whose install failed (for the next run); removes the file when nothing is left to retry
function Save-RemainingInventory([object[]]$Plan, [object[]]$NotBack, [string]$Path) {
    $failed = @($NotBack | Where-Object { $_.Reason -eq 'install failed' } | ForEach-Object { $_.Name })
    $left = [ordered]@{ apps = @(); capabilities = @(); features = @(); programs = @() }
    $listOf = @{ app = 'apps'; capability = 'capabilities'; feature = 'features'; program = 'programs' }
    foreach ($item in $Plan) { if ($failed -contains $item.Name) { $left[$listOf[$item.Kind]] += $item.Name } }
    if ($failed.Count) { [IO.File]::WriteAllText($Path, ($left | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false)) }
    else { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
}
function Invoke-RestorePlan([object[]]$Plan, [scriptblock]$Runner) {
    if (-not $Runner) {
        $Runner = {
            param($item)
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($item.How -eq 'capability') { Add-WindowsCapability -Online -Name $item.Id -ErrorAction Stop | Out-Null; return $true }
            if ($item.How -eq 'feature') { Enable-WindowsOptionalFeature -Online -FeatureName $item.Id -All -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null; return $true }
            if (-not $winget) { return $false }
            $source = if ($item.How -eq 'msstore') { 'msstore' } else { 'winget' }
            $code = Invoke-Winget $winget.Source @('install', '--id', $item.Id, '--exact', '--source', $source, '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
            # -1978335189 (0x8A15002B): already installed and nothing newer, which counts as back
            return ($code -eq 0 -or $code -eq -1978335189)
        }
    }
    $notBack = @()
    foreach ($item in $Plan) {
        if ($item.How -eq 'skip') { $notBack += [pscustomobject]@{ Name = $item.Name; Reason = 'no longer available to install' }; continue }
        $ok = $false
        try { $ok = [bool](& $Runner $item) } catch { }
        if ($ok) { Write-Log "  ok    $($item.Name)" 'Green' }
        else { $notBack += [pscustomobject]@{ Name = $item.Name; Reason = 'install failed' } }
    }
    $notBack
}
$inventoryPath = Join-Path $env:ProgramData 'Cullewie\Work\removed-inventory.json'
$inventory = Get-RemovedInventory $inventoryPath
$restorePlan = if ($inventory) { @(Get-RestorePlan $inventory) } else { @() }

if ($AppsOnly) {
    # the second half of Vanilla, after its restart: the Store installs hung every time in the same session as the
    # service reset (2026-11-23, the Game Bar, three times) and worked every time after a restart
    Unregister-ScheduledTask -TaskName 'cullewie-vanilla-apps' -Confirm:$false -ErrorAction SilentlyContinue
    try { . (Join-Path $PSScriptRoot '..\TestLog.ps1') } catch { }   # TESTLOG
    $appsWatch = [Diagnostics.Stopwatch]::StartNew()
    $until = (Get-Date).AddMinutes(5)
    while (-not (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 5 }
    Write-Log 'Microsoft Store and Xbox apps (after the restart)'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Store-Xbox.ps1') -Apps xbox
    $appsExit = $LASTEXITCODE
    $notBack = @()
    if ($inventory) {
        Write-Log "Removed apps and features: bringing back what can come back ($(@($restorePlan | Where-Object How -ne 'skip').Count) items)"
        $notBack = @(Invoke-RestorePlan $restorePlan)
        foreach ($n in $notBack) { Write-Log "  not restored  $($n.Name) ($($n.Reason))" 'Yellow' }
        # what failed to install stays listed for the next Vanilla run; the rest is used up
        Save-RemainingInventory -Plan $restorePlan -NotBack $notBack -Path $inventoryPath
    }
    $failedApps = @($notBack | Where-Object Reason -eq 'install failed').Count + $(if ($appsExit -ne 0) { 1 } else { 0 })
    if ($failedApps) { Write-Log 'Some apps did not install (listed above); run Vanilla Mode again later to retry them.' 'Yellow' }
    Write-Log "Vanilla apps done. Log: $log" 'Green'
    if (Get-Command Write-TestStep -ErrorAction SilentlyContinue) { Write-TestStep 'Vanilla apps (after restart)' $(if ($failedApps) { 'FAIL' } else { 'PASS' }) $failedApps $appsWatch.Elapsed }   # TESTLOG
    exit 0
}

if ($PlanOnly) {
    $out = @("Vanilla plan $(Get-Date -Format s)", "SERVICES ($($plan.Count) to change, $($stubs.Count) leftover keys to remove)")
    $out += $plan | ForEach-Object { "service`t$($_.Name)`t$($_.From)`t$($_.To)" }
    $out += $stubs | ForEach-Object { "stub`t$_" }
    $out += "POLICIES ($($presentPolicies.Count) present of $($policies.Count) known)"
    $out += $presentPolicies | ForEach-Object { "policy`t$($_.Key)`t$($_.Value)" }
    $out += "DEFENDER ($($defenderValues.Count) values)"
    $out += $defenderValues | ForEach-Object { "defender`t$($_.Key)`t$($_.Value)" }
    $out += if ($appearanceSaved.Count) { "APPEARANCE ($appearanceChanges of $($appearanceSaved.Count) saved values differ)" } else { 'APPEARANCE (no saved copy: Tweaks.ps1 has not run since this version, the look stays as it is)' }
    $out += if ($inventory) { "RESTORE ($(@($restorePlan | Where-Object How -ne 'skip').Count) can come back, $(@($restorePlan | Where-Object How -eq 'skip').Count) cannot)" } else { 'RESTORE (no saved list: All-in ran before this version saved one, nothing is reinstalled)' }
    $out += $restorePlan | ForEach-Object { "restore`t$($_.Kind)`t$($_.Name)`t$($_.How)`t$($_.Id)" }
    Set-Content -Path $PlanPath -Value $out -Encoding UTF8
    Write-Host "Vanilla: plan written to $PlanPath; nothing was changed." -ForegroundColor Green
    exit 0
}

# Runs $Command once as TrustedInstaller (same helper as in Tweaks.ps1)
function Run-Trusted([string]$Command) {
    # the command travels on cmd.exe's command line (8191 characters at most, base64 doubles it): a long batch goes
    # into a file and only "run this file" is sent
    $batch = $null
    if ($Command.Length -gt 1500) {
        $batch = Join-Path $env:ProgramData ('Cullewie\Work\trusted-' + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $batch -Value $Command -Encoding UTF8
        $Command = "Invoke-Expression ([IO.File]::ReadAllText('$batch'))"
    }
    $default = "$env:SystemRoot\servicing\TrustedInstaller.exe"
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller'
    $done = Join-Path $env:ProgramData ('Cullewie\Work\trusted-' + [guid]::NewGuid().ToString('N') + '.done')
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Service TrustedInstaller).Status -ne 'Stopped') {
        if (-not (Get-Process TiWorker -ErrorAction SilentlyContinue)) { Stop-Service TrustedInstaller -ErrorAction SilentlyContinue }
        if ((Get-Date) -gt $deadline) { Write-Host 'TrustedInstaller is busy with Windows servicing; this step was skipped.' -ForegroundColor Yellow; $global:CullewieTrustedFailed = $true; return }
        Start-Sleep -Seconds 2
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("$Command`nSet-Content -LiteralPath '$done' -Value ok"))
    try {
        sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -NoProfile -EncodedCommand $encoded" | Out-Null
        sc.exe start TrustedInstaller | Out-Null
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
    if (Test-Path -LiteralPath $done) {
        Remove-Item -LiteralPath $done -Force
        if ($batch) { Remove-Item -LiteralPath $batch -Force -ErrorAction SilentlyContinue }
    }
    else { Write-Host 'A TrustedInstaller step did not finish in time; it may not be applied.' -ForegroundColor Yellow; $global:CullewieTrustedFailed = $true }
}

Write-Log "Vanilla $(Get-Date -Format s)" 'Cyan'
# backup first: service start values, policy keys
$backup = $log -replace '\.log$', '-backup'
$lines = @('Windows Registry Editor Version 5.00', '')
foreach ($p in $plan) { $lines += "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($p.Name)]", ('"Start"=dword:{0:x8}' -f [int]$p.From), '' }
Set-Content -Path "$backup-services.reg" -Value $lines -Encoding Unicode
cmd /c "reg export HKLM\SOFTWARE\Policies `"$backup-policies-hklm.reg`" /y >nul 2>&1"
cmd /c "reg export HKCU\SOFTWARE\Policies `"$backup-policies-hkcu.reg`" /y >nul 2>&1"
Write-Log "Backup: $backup-*.reg" 'Cyan'

Write-Log "Services: $($plan.Count) to their Windows defaults, $($stubs.Count) leftover keys removed"
$needTrusted = New-Object System.Collections.Generic.List[object]
foreach ($p in $plan) {
    try {
        Set-ItemProperty -Path "$serviceRoot\$($p.Name)" -Name Start -Value $p.To -Type DWord -ErrorAction Stop
        if ($p.To -eq 2) { Set-ItemProperty -Path "$serviceRoot\$($p.Name)" -Name DelayedAutostart -Value $p.Delayed -Type DWord -ErrorAction Stop }
    }
    catch {
        $mode = if ($p.To -eq 2 -and $p.Delayed) { 'delayed-auto' } else { @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[$p.To] }
        sc.exe config $p.Name start= $mode | Out-Null
        if ((Get-ItemProperty "$serviceRoot\$($p.Name)").Start -ne $p.To) { $needTrusted.Add($p) }
    }
}
foreach ($s in $stubs) { Remove-Item -Path "$serviceRoot\$s" -Force -ErrorAction SilentlyContinue }
if ($needTrusted.Count) {
    $cmds = $needTrusted | ForEach-Object {
        "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\$($_.Name)`" /v Start /t REG_DWORD /d $($_.To) /f"
        if ($_.To -eq 2) { "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\$($_.Name)`" /v DelayedAutostart /t REG_DWORD /d $($_.Delayed) /f" }
    }
    Run-Trusted ($cmds -join "`n")
}
$notApplied = @($plan | Where-Object { (Get-ItemProperty "$serviceRoot\$($_.Name)" -ErrorAction SilentlyContinue).Start -ne $_.To } | ForEach-Object Name)
if ($notApplied) { Write-Log "  not applied: $($notApplied -join ', ')" 'Red' }

Write-Log 'Network: IPv6, file sharing, QoS and discovery back on (Teredo: set by the Xbox step below)'
# only the bindings that are off: re-binding restarts the adapter, and the connection drops for a few seconds
$offBindings = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6', 'ms_server', 'ms_msclient', 'ms_pacer', 'ms_lldp', 'ms_lltdio', 'ms_rspndr' -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
if ($offBindings) {
    # Not now: with the services All-in disabled still loaded, switching a binding on while Windows runs hung (10 minutes)
    # or cut the connection until a manual restart (2026-11-23), and the Store/Xbox step below needs the internet.
    # A one-time task switches them on at the next startup, as SYSTEM, before anyone signs in, then removes itself.
    $bindingCommand = (@($offBindings | ForEach-Object { "Enable-NetAdapterBinding -Name '$($_.Name -replace "'", "''")' -ComponentID '$($_.ComponentID)' -ErrorAction SilentlyContinue" }) -join '; ') +
        "; Unregister-ScheduledTask -TaskName 'cullewie-bindings' -Confirm:`$false"
    $encodedBindings = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bindingCommand))
    $bindingAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedBindings"
    $bindingTrigger = New-ScheduledTaskTrigger -AtStartup
    $bindingPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    try {
        Register-ScheduledTask -TaskName 'cullewie-bindings' -Action $bindingAction -Trigger $bindingTrigger -Principal $bindingPrincipal -Force -ErrorAction Stop | Out-Null
        Write-Log "  $($offBindings.Count) bindings go back on at the restart (now would cut the connection)"
    }
    catch { Write-Log "  could not schedule the bindings for the restart: $($_.Exception.Message)" 'Red' }
}
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -ErrorAction SilentlyContinue

Write-Log "Policies: $($presentPolicies.Count) values removed"
foreach ($p in $presentPolicies) { Remove-ItemProperty -Path "Registry::$($p.Key)" -Name $p.Value -ErrorAction SilentlyContinue }
$policyLeft = @($presentPolicies | Where-Object { $null -ne (Get-ItemProperty -Path "Registry::$($_.Key)" -Name $_.Value -ErrorAction SilentlyContinue) })
if ($policyLeft) {
    Run-Trusted (($policyLeft | ForEach-Object { "reg delete `"$($_.Key)`" /v `"$($_.Value)`" /f" }) -join "`n")
}

Write-Log "Defender: $($defenderValues.Count) values back to Windows defaults, scheduled scans on"
# HKEY_CURRENT_USER values belong to the user running this, so they are removed here; as TrustedInstaller (SYSTEM)
# HKEY_CURRENT_USER would be SYSTEM's own hive
$userValues = @($defenderValues | Where-Object { $_.Key -like 'HKEY_CURRENT_USER\*' })
foreach ($v in $userValues) { Remove-ItemProperty -Path "Registry::$($v.Key)" -Name $v.Value -ErrorAction SilentlyContinue }
$machineValues = @($defenderValues | Where-Object { $_.Key -notlike 'HKEY_CURRENT_USER\*' })
if ($machineValues) {
    Run-Trusted (($machineValues | ForEach-Object {
        if ($null -ne $_.Default) { "reg add `"$($_.Key)`" /v `"$($_.Value)`" /t REG_DWORD /d $($_.Default) /f" }
        else { "reg delete `"$($_.Key)`" /v `"$($_.Value)`" /f" }
    }) -join "`n")
}
# Defender keeps cloud protection and sample submission in values it guards itself; its own cmdlet sets the defaults
Set-MpPreference -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -ErrorAction SilentlyContinue
foreach ($task in 'Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh', 'Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance',
                  'Microsoft\Windows\Windows Defender\Windows Defender Cleanup', 'Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan',
                  'Microsoft\Windows\Windows Defender\Windows Defender Verification') {
    schtasks /Change /TN $task /Enable 2>$null | Out-Null
}

Write-Log 'Power: Windows default plans, hibernation, fast startup, Lock and Sleep in the power menu'
cmd /c "powercfg -restoredefaultschemes >nul 2>&1"
cmd /c "powercfg /hibernate on >nul 2>&1"
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings' -Name 'ShowLockOption', 'ShowSleepOption' -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -ErrorAction SilentlyContinue

Write-Log 'Timer Resolution service removed'
if (Get-Service -Name 'Set Timer Resolution Service' -ErrorAction SilentlyContinue) {
    Stop-Service -Name 'Set Timer Resolution Service' -Force -ErrorAction SilentlyContinue
    sc.exe delete 'Set Timer Resolution Service' | Out-Null
}
Remove-Item "$env:SystemDrive\Windows\SetTimerResolutionService.exe" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'GlobalTimerResolutionRequests' -ErrorAction SilentlyContinue

Write-Log 'Scheduled disk optimization (TRIM on SSDs) on'
Get-ScheduledTask -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue | Enable-ScheduledTask | Out-Null

Write-Log 'System Restore on, Store auto-update and background apps on, Windows Update drivers back'
Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate' -Name 'AutoDownload' -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 1 -Type DWord -ErrorAction SilentlyContinue

if ($appearanceSaved.Count) {
    $restored = Restore-AppearanceBackup $appearanceSaved
    Write-Log "Appearance: your own theme, colours, effects, scaling, taskbar, Start menu and Explorer settings back ($restored values; saved by All-in before it changed them)"
    # used up: the next All-in run saves the look as it is then
    Remove-Item -LiteralPath $appearanceBackup -Force -ErrorAction SilentlyContinue
}
else { Write-Log 'Appearance: no saved copy of your own settings (All-in ran before this version saved one), so the look stays as it is' 'Yellow' }

# Store / Xbox apps and the removed apps: after the restart, by a one-time logon task (this script with -AppsOnly).
# Installing them here, in the same session as the service reset, hung (2026-11-23, the Game Bar, three times).
Write-Log 'Microsoft Store and Xbox apps, and the removed apps: installed after the restart, at sign-in'
if (-not $inventory) { Write-Log '  (no saved list of removed apps: All-in ran before this version saved one, so only Store and Xbox)' 'Yellow' }
try {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $appsAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -AppsOnly"
    $appsTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $appsPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $appsSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromHours(2))
    Register-ScheduledTask -TaskName 'cullewie-vanilla-apps' -Action $appsAction -Trigger $appsTrigger -Principal $appsPrincipal -Settings $appsSettings -Force -ErrorAction Stop | Out-Null
}
catch { Write-Log "  could not schedule the app installs: $($_.Exception.Message). Run Vanilla Mode again after the restart." 'Red' }

Write-Log "Vanilla done. Not undone: BitLocker, and apps that are no longer offered. Restart Windows now: the look, scaling, network and features apply then, and the apps install by themselves after you sign in. Log: $log" 'Green'
# a setting that did not apply makes the run a failure (apps that do not install later do not)
if ($notApplied -or $global:CullewieTrustedBroken -or $global:CullewieTrustedFailed) { exit 1 }
exit 0
