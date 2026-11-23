# Vanilla: undoes this toolkit's Windows changes and goes back to Windows 11 defaults. GPU drivers and GPU settings stay.
#  - services: every service Services.ps1 touches gets its Windows 11 default start type; keys an earlier run created for
#    services that do not exist on this PC (only a "Start" value) are removed
#  - network: IPv6, file sharing (SMB), QoS and network discovery bindings back on, Teredo default, IPv4 preference off
#  - policies: every policy value Tweaks.ps1, Defender.ps1 or the Store/Xbox option writes is removed (exported first)
#  - Defender: SmartScreen, cloud protection, Smart App Control state values removed (Windows defaults), scheduled scans on
#  - power plans restored, Timer Resolution service removed, System Restore on, Store auto-update and background apps on
#  - Microsoft Store and Xbox apps installed (Store-Xbox.ps1 -Apps xbox)
# Not undone: BitLocker (turn it on yourself), other removed Store apps (install them from the Store), personal settings
# such as the dark theme, 100% scaling or Explorer options (their "default" differs per PC).
# -PlanOnly: write what would change to -PlanPath and stop; nothing is changed. Restart Windows afterwards.
param([switch]$PlanOnly, [string]$PlanPath = "$env:ProgramData\Cullewie\Work\vanilla-plan.txt")
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$work = Join-Path $env:ProgramData 'Cullewie\Work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$log = Join-Path $work ('vanilla-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
function Write-Log([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color; if (-not $PlanOnly) { Add-Content -Path $log -Value $Text -Encoding UTF8 } }

# ---------- Windows 11 default start types ----------
# 2 = automatic, 4 = disabled by default; every other service the toolkit touches defaults to 3 (manual / on demand)
$autoStart = @('AudioEndpointBuilder', 'Audiosrv', 'BITS', 'BrokerInfrastructure', 'edgeupdate', 'CDPSvc', 'CDPUserSvc', 'CoreMessagingRegistrar',
    'CryptSvc', 'DcomLaunch', 'Dhcp', 'DiagTrack', 'DispBrokerDesktopSvc', 'Dnscache', 'DPS', 'DusmSvc', 'EventLog', 'gpsvc',
    'iphlpsvc', 'LanmanServer', 'LSM', 'MapsBroker', 'nsi', 'OneSyncSvc', 'PcaSvc', 'Power', 'ProfSvc', 'RpcEptMapper', 'RpcSs',
    'Schedule', 'SENS', 'SgrmBroker', 'ShellHWDetection', 'Spooler', 'sppsvc', 'SysMain', 'SystemEventsBroker',
    'TextInputManagementService', 'TrkWks', 'UserManager', 'UsoSvc', 'Winmgmt', 'WlanSvc', 'WpnService', 'WpnUserService', 'WSearch')
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
        if ($now -ne $want) { $plan.Add([pscustomobject]@{ Name = $key.PSChildName; From = $now; To = $want }) }
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
$defenderText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Defender.ps1'))
$defenderValues = @([regex]::Matches($defenderText, 'reg add `"(HKEY_[^`]+)`" /v `"([^`]+)`"') | ForEach-Object { [pscustomobject]@{ Key = $_.Groups[1].Value; Value = $_.Groups[2].Value } } |
    # not here: Tamper Protection (Windows Security only), cloud protection and samples (Spynet: set below with
    # Set-MpPreference, Defender guards those values), real-time protection (Defender.ps1 writes 0 = on, the default)
    Where-Object { $_.Key -notmatch '\\Policies\\' -and $_.Key -notmatch '\\Spynet$' -and $_.Value -notin 'TamperProtection', 'DisableRealtimeMonitoring' } | Sort-Object Key, Value -Unique |
    # only the values still set: a value that is already gone is the Windows default
    Where-Object { $null -ne (Get-ItemProperty -Path "Registry::$($_.Key)" -Name $_.Value -ErrorAction SilentlyContinue) })

if ($PlanOnly) {
    $out = @("Vanilla plan $(Get-Date -Format s)", "SERVICES ($($plan.Count) to change, $($stubs.Count) leftover keys to remove)")
    $out += $plan | ForEach-Object { "service`t$($_.Name)`t$($_.From)`t$($_.To)" }
    $out += $stubs | ForEach-Object { "stub`t$_" }
    $out += "POLICIES ($($presentPolicies.Count) present of $($policies.Count) known)"
    $out += $presentPolicies | ForEach-Object { "policy`t$($_.Key)`t$($_.Value)" }
    $out += "DEFENDER ($($defenderValues.Count) values)"
    $out += $defenderValues | ForEach-Object { "defender`t$($_.Key)`t$($_.Value)" }
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
    try { Set-ItemProperty -Path "$serviceRoot\$($p.Name)" -Name Start -Value $p.To -Type DWord -ErrorAction Stop }
    catch {
        sc.exe config $p.Name start= $(@{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[$p.To]) | Out-Null
        if ((Get-ItemProperty "$serviceRoot\$($p.Name)").Start -ne $p.To) { $needTrusted.Add($p) }
    }
}
foreach ($s in $stubs) { Remove-Item -Path "$serviceRoot\$s" -Force -ErrorAction SilentlyContinue }
if ($needTrusted.Count) {
    $cmds = $needTrusted | ForEach-Object { "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\$($_.Name)`" /v Start /t REG_DWORD /d $($_.To) /f" }
    Run-Trusted ($cmds -join "`n")
}
$notApplied = @($plan | Where-Object { (Get-ItemProperty "$serviceRoot\$($_.Name)" -ErrorAction SilentlyContinue).Start -ne $_.To } | ForEach-Object Name)
if ($notApplied) { Write-Log "  not applied: $($notApplied -join ', ')" 'Red' }

Write-Log 'Network: IPv6, file sharing, QoS and discovery back on; Teredo default'
# only the bindings that are off: re-binding restarts the adapter, and the connection drops for a few seconds
$offBindings = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6', 'ms_server', 'ms_msclient', 'ms_pacer', 'ms_lldp', 'ms_lltdio', 'ms_rspndr' -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
if ($offBindings) {
    Write-Log '  (the network connection drops for a few seconds while the adapter restarts)'
    $offBindings | ForEach-Object { Enable-NetAdapterBinding -Name $_.Name -ComponentID $_.ComponentID -ErrorAction SilentlyContinue }
}
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -ErrorAction SilentlyContinue
netsh interface teredo set state type=default | Out-Null

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
if ($machineValues) { Run-Trusted (($machineValues | ForEach-Object { "reg delete `"$($_.Key)`" /v `"$($_.Value)`" /f" }) -join "`n") }
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

Write-Log 'System Restore on, Store auto-update and background apps on, Windows Update drivers back'
Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate' -Name 'AutoDownload' -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Log 'Microsoft Store and Xbox apps'
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Store-Xbox.ps1') -Apps xbox
$appsExit = $LASTEXITCODE

Write-Log "Vanilla done. Not undone: BitLocker, other removed Store apps, personal settings (theme, scaling, Explorer). Restart Windows now. Log: $log" 'Green'
if ($notApplied -or $global:CullewieTrustedBroken -or $global:CullewieTrustedFailed -or $appsExit -ne 0) { exit 1 }
exit 0
