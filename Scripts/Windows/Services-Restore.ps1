# Puts back the Windows default start type of the services that Services.ps1 used to disable and that Windows,
# networking, sign-in or app installs need. Backs up the current values first. Restart afterwards.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# Windows 11 defaults: 2 = automatic, 3 = manual
$defaults = [ordered]@{
    # networking: WlanSvc needs Wcmsvc, Wcmsvc needs WinHttpAutoProxySvc
    WinHttpAutoProxySvc = 3; Wcmsvc = 2; NlaSvc = 2; LanmanWorkstation = 2; NcbService = 3
    # firewall and Defender network protection need BFE
    BFE = 2; mpssvc = 2
    # SENS needs EventSystem
    EventSystem = 2
    # devices and drivers
    PlugPlay = 3; DsmSvc = 3; DevQueryBroker = 3
    # Store and MSIX installs (Claude Desktop, ChatGPT)
    ClipSVC = 3; LicenseManager = 3; AppReadiness = 3; InstallService = 3; DoSvc = 3; StorSvc = 3
    # accounts, saved passwords and app sign-in
    SamSs = 2; VaultSvc = 3; TokenBroker = 3; wlidsvc = 3
    # desktop
    Themes = 2; FontCache = 2
}

$work = Join-Path $env:ProgramData 'Cullewie\Work'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$log = Join-Path $work "services-restore-$(Get-Date -Format yyyyMMdd-HHmmss).log"
function Write-Log([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color; Add-Content -Path $log -Value $Text -Encoding UTF8 }

# backup: current start values, re-importable as a .reg file
$backup = $log -replace '\.log$', '-backup.reg'
$lines = @('Windows Registry Editor Version 5.00', '')
foreach ($name in $defaults.Keys) {
    $start = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name Start -ErrorAction SilentlyContinue).Start
    if ($null -ne $start) { $lines += "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$name]", ('"Start"=dword:{0:x8}' -f $start), '' }
}
Set-Content -Path $backup -Value $lines -Encoding Unicode
Write-Log "Backup: $backup" 'Cyan'

$failed = 0
foreach ($name in $defaults.Keys) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path $key)) { Write-Log "skip  $name (not on this PC)"; continue }
    $old = (Get-ItemProperty $key -Name Start).Start
    $new = $defaults[$name]
    if ($old -eq $new) { Write-Log "ok    $name already $new"; continue }
    try {
        Set-ItemProperty -Path $key -Name Start -Value $new -Type DWord
        Write-Log "fixed $name $old -> $new" 'Green'
    }
    catch {
        # some keys only allow TrustedInstaller; sc.exe goes through the service manager instead
        $mode = @{ 2 = 'auto'; 3 = 'demand' }[$new]
        sc.exe config $name start= $mode | Out-Null
        if ((Get-ItemProperty $key -Name Start).Start -eq $new) { Write-Log "fixed $name $old -> $new (sc)" 'Green' }
        else { Write-Log "FAIL  $name stays $old : $($_.Exception.Message)" 'Red'; $failed++ }
    }
}

if ($failed) { Write-Log "$failed service(s) could not be changed. Log: $log" 'Red'; exit 1 }
Write-Log "Done. Restart Windows for the changes to apply. Log: $log" 'Green'
exit 0
