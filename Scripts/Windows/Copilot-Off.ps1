# SCRIPT RUN AS ADMIN
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
Exit}
$Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.PrivateData.ProgressBackgroundColor = "Black"
$Host.PrivateData.ProgressForegroundColor = "White"
Clear-Host

# SCRIPT SILENT
$progresspreference = 'silentlycontinue'

Write-Host "Copilot: Off...`n"

# stop related processes
$stop = "backgroundTaskHost", "Copilot", "CrossDeviceResume", "GameBar", "MicrosoftEdgeUpdate", "msedge", "msedgewebview2", "OneDrive", "OneDrive.Sync.Service", "OneDriveStandaloneUpdater", "Resume", "RuntimeBroker", "Search", "SearchHost", "Setup", "StoreDesktopExtension", "WidgetService", "Widgets"
$stop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
Get-Process | Where-Object { $_.ProcessName -like "*edge*" } | Stop-Process -Force -ErrorAction SilentlyContinue

# remove copilot package for all users
Get-AppxPackage -AllUsers *Copilot* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# remove provisioned package so new/reset user profiles don't get it reinstalled
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*Copilot*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# disable via policy as a backstop against future re-provisioning
cmd /c "reg add `"HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot`" /v `"TurnOffWindowsCopilot`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot`" /v `"TurnOffWindowsCopilot`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

Write-Host "Done.`n"
Read-Host "Devam etmek icin Enter'a basin"
exit
