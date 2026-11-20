        # SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host

        Write-Host "1. Widgets: Off (Recommended)"
        while ($true) {
        $choice = Read-Host " "
        if ($choice -match '^[1]$') {
        switch ($choice) {
        1 {

Clear-Host

# disable widgets regedit
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests`" /v `"value`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# remove windows widgets from taskbar regedit
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Dsh`" /v `"AllowNewsAndInterests`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# stop widgets running
Stop-Process -Force -Name Widgets -ErrorAction SilentlyContinue | Out-Null
Stop-Process -Force -Name WidgetService -ErrorAction SilentlyContinue | Out-Null

exit

          }
        } } else { Write-Host "Invalid input. Please select a valid option (1)." } }