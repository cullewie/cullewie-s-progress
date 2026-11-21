[CmdletBinding()]
param(
    # Full setup: Services restarts the computer later, so this run only queues the safe-mode step.
    [switch]$NoRestart
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

# Adapted from FR33THY "33 Defender Optimize.ps1".
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

        # FUNCTION RUN AS TRUSTED INSTALLER
        function Run-Trusted([String]$command) {
        try {
    	Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction Stop
  		}
  		catch {
    	taskkill /im trustedinstaller.exe /f >$null
  		}
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
        $DefaultBinPath = $service.PathName
  		$trustedInstallerPath = "$env:SystemRoot\servicing\TrustedInstaller.exe"
  		if ($DefaultBinPath -ne $trustedInstallerPath) {
    	$DefaultBinPath = $trustedInstallerPath
  		}
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
        $base64Command = [Convert]::ToBase64String($bytes)
        sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -encodedcommand $base64Command" | Out-Null
        sc.exe start TrustedInstaller | Out-Null
        sc.exe config TrustedInstaller binpath= "`"$DefaultBinPath`"" | Out-Null
        try {
    	Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction Stop
  		}
  		catch {
    	taskkill /im trustedinstaller.exe /f >$null
  		}
        }

# these settings only apply in safe mode; if Windows started normally, queue this step again and restart into safe mode
if ((Get-CimInstance Win32_ComputerSystem).BootupState -eq 'Normal boot') {
Remove-Item "$env:SystemRoot\Temp\defenderoptimize.norestart" -Force -ErrorAction SilentlyContinue
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*defenderoptimize`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:SystemRoot\Temp\defenderoptimize.ps1`" /f >nul 2>&1"
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"
Write-Host "Restarting into safe mode`n" -ForegroundColor Red
Start-Sleep -Seconds 5
shutdown -r -t 00
exit
}

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
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Epoch`" /v `"Epoch`" /t REG_DWORD /d `"1231`" /f >nul 2>&1"',
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
'cmd /c "reg add `"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost`" /v `"EnableWebContentEvaluation`" /t REG_DWORD /d `"0`" /f >nul 2>&1"',

# local security authority protection
'cmd /c "reg add `"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa`" /v `"RunAsPPL`" /t REG_DWORD /d `"0`" /f >nul 2>&1"'
)

# run $windowssecuritysettings as function with trusted installer
foreach ($command in $windowssecuritysettings) {
    Run-Trusted $command
}

# run $windowssecuritysettings as admin
foreach ($command in $windowssecuritysettings) {
    Invoke-Expression $command
}

# full setup: Services Off runs next in this same safe boot, then removes safe boot and restarts
$noRestartMarker = "$env:SystemRoot\Temp\defenderoptimize.norestart"
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
'@
Set-Content -Path "$env:SystemRoot\Temp\defenderoptimize.ps1" -Value $DefenderOptimize -Force
if ($NoRestart) { Set-Content -Path "$env:SystemRoot\Temp\defenderoptimize.norestart" -Value '' -Force }
else { Remove-Item "$env:SystemRoot\Temp\defenderoptimize.norestart" -Force -ErrorAction SilentlyContinue }

# install runonce defenderoptimize ps1 file to run in safe boot
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"*defenderoptimize`" /t REG_SZ /d `"powershell.exe -nop -ep bypass -WindowStyle Maximized -f $env:SystemRoot\Temp\defenderoptimize.ps1`" /f >nul 2>&1"

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

# turn on safe boot
cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"

if ($NoRestart) {
    Write-Host "Defender changes run in safe mode at the next restart.`n" -ForegroundColor Yellow
    exit
}

Write-Host "Restarting`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00

exit
