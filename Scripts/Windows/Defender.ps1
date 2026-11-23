[CmdletBinding()]
param(
    # Full setup: write the safe-mode script only; the launcher's safe-mode step runs it and restarts.
    [switch]$QueueOnly
)

        # SCRIPT RUN AS ADMIN (keep -QueueOnly, or the elevated copy would restart into safe mode right away)
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"{1}" -f $PSCommandPath, $(if ($QueueOnly) { ' -QueueOnly' } else { '' })) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host
        New-Item -ItemType Directory -Path "$env:ProgramData\Cullewie\Work" -Force | Out-Null

# Kept as Windows default because FACEIT Anti-Cheat needs them: virtualization based
# security (hypervisor, VBS), memory integrity, the vulnerable driver blocklist and
# system exploit protection (MitigationOptions).

Write-Host "Defender Optimize: On...`n"

# create defenderoptimize ps1 file
$DefenderOptimize = @'
        # SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host

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

# these settings only apply in safe mode; if Windows started normally, queue this step again and restart into safe mode
if ((Get-CimInstance Win32_ComputerSystem).BootupState -eq 'Normal boot') {
Remove-Item "$env:ProgramData\Cullewie\Work\defenderoptimize.norestart" -Force -ErrorAction SilentlyContinue
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*defenderoptimize`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:ProgramData\Cullewie\Work\defenderoptimize.ps1`" /f >nul 2>&1"
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"
Write-Host "Restarting into safe mode`n" -ForegroundColor Red
Start-Sleep -Seconds 5
shutdown -r -t 00
exit
}
# leave safe mode first: if power fails or something hangs below, the next start is normal Windows
cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"

Write-Host "Defender Optimize: On...`n"

$windowssecuritysettings = @(
# virus & threat protection - manage settings
# real time protection - needs safe boot as trusted installer - windows turns this back on automatically
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection`" /v `"DisableRealtimeMonitoring`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# dev drive protection - needs safe boot as trusted installer
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection`" /v `"DisableAsyncScanOnOpen`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',

# cloud delivered protection - needs safe boot as trusted installer
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet`" /v `"SpyNetReporting`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# automatic sample submission
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet`" /v `"SubmitSamplesConsent`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# tamper protection - needs safe boot as trusted installer
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features`" /v `"TamperProtection`" /t REG_DWORD /d `"4`" /f >nul 2>&1"',

# virus & threat protection - manage ransomware protection
# controlled folder access
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access`" /v `"EnableControlledFolderAccess`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# firewall & network protection - firewall notification settings - manage notifications
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications`" /v `"DisableEnhancedNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection`" /v `"NoActionNotificationDisabled`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection`" /v `"SummaryNotificationDisabled`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection`" /v `"FilesBlockedNotificationDisabled`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection`" /v `"DisableNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection`" /v `"DisableDynamiclockNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection`" /v `"DisableWindowsHelloNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile`" /v `"DisableNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile`" /v `"DisableNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile`" /v `"DisableNotifications`" /t REG_DWORD /d `"1`" /f >nul 2>&1"',

# app & browser control - smart app control settings
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender`" /v `"VerifiedAndReputableTrustModeEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender`" /v `"SmartLockerMode`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender`" /v `"PUAProtection`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Control\AppID\Configuration\SMARTLOCKER`" /v `"START_PENDING`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Control\AppID\Configuration\SMARTLOCKER`" /v `"ENABLED`" /t REG_BINARY /d `"0000000000000000`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Control\CI\Policy`" /v `"VerifiedAndReputablePolicyState`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# app & browser control - reputation based protection settings
# check apps and files
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer`" /v `"SmartScreenEnabled`" /t REG_SZ /d `"Off`" /f >nul 2>&1"',

# smartscreen for microsoft edge - needs normal boot as admin
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenEnabled`" /ve /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled`" /ve /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# phishing protection
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components`" /v `"CaptureThreatWindow`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components`" /v `"NotifyMalicious`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components`" /v `"NotifyPasswordReuse`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components`" /v `"NotifyUnsafeApp`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components`" /v `"ServiceEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# smartscreen for microsoft store apps - needs normal boot as admin
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost`" /v `"EnableWebContentEvaluation`" /t REG_DWORD /d `"0`" /f >nul 2>&1"'

)

# run $windowssecuritysettings with trusted installer, all in one start
# (a second start fails while the previous one is still pending, so one call per command skipped most of them)
$trustedPs1 = "$env:ProgramData\Cullewie\Work\defender-trusted.ps1"
Set-Content -Path $trustedPs1 -Value ($windowssecuritysettings -join "`n") -Force
Run-Trusted "Invoke-Expression ([IO.File]::ReadAllText('$trustedPs1'))"
# keep the file if the step timed out: TrustedInstaller may still be reading it
if (-not $global:CullewieTrustedFailed) { Remove-Item $trustedPs1 -Force -ErrorAction SilentlyContinue }

# run $windowssecuritysettings as admin
foreach ($command in $windowssecuritysettings) {
    Invoke-Expression $command
}

# full setup: the launcher's safe-mode step removes safe boot and restarts after this script
$noRestartMarker = "$env:ProgramData\Cullewie\Work\defenderoptimize.norestart"
if (Test-Path $noRestartMarker) {
Remove-Item $noRestartMarker -Force
} else {

# remove safe mode boot
cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"

Write-Host "Restarting`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00
}
if ($global:CullewieTrustedFailed -or $global:CullewieTrustedBroken) { exit 1 }
'@
Set-Content -Path "$env:ProgramData\Cullewie\Work\defenderoptimize.ps1" -Value $DefenderOptimize -Force
if ($QueueOnly) {
Set-Content -Path "$env:ProgramData\Cullewie\Work\defenderoptimize.norestart" -Value '' -Force
} else {
Remove-Item "$env:ProgramData\Cullewie\Work\defenderoptimize.norestart" -Force -ErrorAction SilentlyContinue

# install runonce defenderoptimize ps1 file to run in safe boot
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*defenderoptimize`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:ProgramData\Cullewie\Work\defenderoptimize.ps1`" /f >nul 2>&1"
}

# smartscreen for microsoft edge - needs normal boot as admin
cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenEnabled`" /ve /t REG_DWORD /d `"0`" /f >nul 2>&1"

# smartscreen for microsoft store apps - needs normal boot as admin
cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost`" /v `"EnableWebContentEvaluation`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# scheduled tasks - needs normal boot as admin
schtasks /Change /TN "Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh" /Disable 2>$null | Out-Null
schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance" /Disable 2>$null | Out-Null
schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cleanup" /Disable 2>$null | Out-Null
schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan" /Disable 2>$null | Out-Null
schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Verification" /Disable 2>$null | Out-Null

if ($QueueOnly) {
    Write-Host "Defender changes are ready for the full setup safe-mode step.`n" -ForegroundColor Yellow
    exit
}

# turn on safe boot
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"

Write-Host "Restarting`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00

exit
