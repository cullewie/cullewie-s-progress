[CmdletBinding()]
param(
    # Set by the full setup logon task after the first safe-mode restart.
    [switch]$ResumeFullSetup
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepoRoot = $PSScriptRoot
$script:PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$script:Tools = @(
    [pscustomobject]@{ Id='nvidia-updater'; Name='NVIDIA Driver Updater'; Category='Drivers'; Path='Scripts/Drivers/NVIDIA/NVIDIA-Driver-Updater.ps1'; Wrapper='NvidiaCase' }
    [pscustomobject]@{ Id='multi-gpu'; Name='Multi-GPU Driver Downloader'; Category='Drivers'; Path='Scripts/Drivers/Multi-GPU/Driver-Downloader.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='ddu'; Name='DDU Auto/Manual'; Category='Drivers'; Path='Scripts/Drivers/DDU/DDU.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='debloated-installer'; Name='Debloated Driver Installer'; Category='Drivers'; Path='Scripts/Drivers/Debloated-Installer/Driver-Installer.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='settings-github'; Name='NVIDIA Settings (GitHub)'; Category='NVIDIA'; Path='Scripts/NVIDIA/Settings-GitHub.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='digital-vibrance'; Name='NVIDIA Digital Vibrance'; Category='NVIDIA'; Path='Scripts/NVIDIA/Digital-Vibrance.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='p0-state'; Name='NVIDIA P0 State On'; Category='NVIDIA'; Path='Scripts/NVIDIA/P0-State.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='widgets'; Name='Widgets Off'; Category='Windows'; Path='Scripts/Windows/Widgets.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='services'; Name='Services Off'; Category='Windows'; Path='Scripts/Windows/Services.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='power-plan'; Name='Power Plan On'; Category='Windows'; Path='Scripts/Windows/Power-Plan.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='copilot-off'; Name='Copilot Off'; Category='Windows'; Path='Scripts/Windows/Copilot-Off.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='timer-resolution'; Name='Timer Resolution On'; Category='Windows'; Path='Scripts/Windows/Timer-Resolution.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='tweaks'; Name='Windows Tweaks'; Category='Windows'; Path='Scripts/Windows/Tweaks.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='defender'; Name='Defender Optimize'; Category='Windows'; Path='Scripts/Windows/Defender.ps1'; Wrapper='' }
)
function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Invoke-ChildScript {
    param(
        [Parameter(Mandatory=$true)]$Tool,
        [string[]]$Arguments = @(),
        [switch]$NoPause
    )
    $script:LastChildExitCode = -1
    $sourcePath = Join-Path $script:RepoRoot ($Tool.Path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Write-Host "Script missing: $sourcePath" -ForegroundColor Red
        return
    }
    Write-Host ([Environment]::NewLine + $Tool.Name) -ForegroundColor Cyan
    Write-Host 'The selected script opens in a separate PowerShell process.' -ForegroundColor Gray
    $launchPath = $sourcePath
    $generatedWrapper = $null
    try {
        if ($Tool.Wrapper -eq 'NvidiaCase') {
            $original = [System.IO.File]::ReadAllText($sourcePath)
            if ($original -notmatch '^\s*1\s*\{' -or $original -notmatch '\}\s*$') {
                throw 'The NVIDIA source no longer matches the expected 1 { ... } case excerpt. Refusing to wrap it.'
            }
            $wrapped = 'switch (1) {' + [Environment]::NewLine + $original.TrimEnd() + [Environment]::NewLine + '}'
            # Admin-only release folder: a non-admin program cannot swap the file before it runs elevated.
            $generatedWrapper = Join-Path $script:RepoRoot ('nvidia-updater-' + [Guid]::NewGuid().ToString('N') + '.ps1')
            Set-Content -LiteralPath $generatedWrapper -Value $wrapped -Encoding UTF8
            $launchPath = $generatedWrapper
        }
        $childArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launchPath) + $Arguments
        & $script:PowerShellExe @childArguments
        $childExitCode = $LASTEXITCODE
        $script:LastChildExitCode = [int]$childExitCode
        if ($childExitCode -ne 0) {
            Write-Host "Child process exit code: $childExitCode" -ForegroundColor Red
        }
        else {
            Write-Host 'Child process finished. Review its own output to confirm what changed.' -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Could not launch $($Tool.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($generatedWrapper -and (Test-Path -LiteralPath $generatedWrapper)) {
            Remove-Item -LiteralPath $generatedWrapper -Force
        }
    }
    if (-not $NoPause) {
        [void](Read-Host 'Press Enter to return to the launcher')
    }
}
function Show-ToolMenu {
    param([Parameter(Mandatory=$true)][string]$Category)
    $items = @($script:Tools | Where-Object { $_.Category -eq $Category })
    while ($true) {
        Clear-Host
        Write-Host "=== $Category ===" -ForegroundColor Cyan
        for ($index = 0; $index -lt $items.Count; $index++) {
            Write-Host ("{0}. {1}" -f ($index + 1), $items[$index].Name)
        }
        Write-Host '0. Back'
        $selection = Read-Host 'Choose a script'
        if ($selection -eq '0') { return }
        $number = 0
        if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $items.Count) {
            Write-Host 'Invalid choice.' -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }
        Invoke-ChildScript -Tool $items[$number - 1]
    }
}
function Start-GuidedNvidiaSetup {
    $updater = $script:Tools | Where-Object { $_.Id -eq 'nvidia-updater' } | Select-Object -First 1
    $statePath = Join-Path $script:RepoRoot 'nvidia-setup-state.json'

    $nvidiaDriver = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -like 'PCI\VEN_10DE&*' -and $_.DriverProviderName -match 'NVIDIA' } |
        Select-Object -First 1
    if ($nvidiaDriver) {
        if ([string]::IsNullOrWhiteSpace([string]$nvidiaDriver.DeviceName)) {
            throw 'Could not save the NVIDIA model name before DDU cleanup.'
        }
        $state = [pscustomobject]@{ GpuName = [string]$nvidiaDriver.DeviceName }
        [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        Write-Host "Installed NVIDIA driver detected for $($nvidiaDriver.DeviceName). DDU will clean NVIDIA in normal Windows mode without restarting." -ForegroundColor Yellow
        $ddu = $script:Tools | Where-Object { $_.Id -eq 'ddu' } | Select-Object -First 1
        Invoke-ChildScript -Tool $ddu -Arguments @('-GuidedNvidia') -NoPause
        if ($script:LastChildExitCode -ne 0) {
            throw 'DDU did not complete. NVIDIA installation was stopped.'
        }
    }
    else {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        Write-Host 'No installed NVIDIA display driver was detected. Skipping DDU.' -ForegroundColor Cyan
    }

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$state.GpuName)) {
            throw 'The saved NVIDIA model name is empty.'
        }
        $env:CULLEWIE_NVIDIA_GPU_NAME = [string]$state.GpuName
    }
    try {
        Write-Host 'Installing NVIDIA display driver.' -ForegroundColor Cyan
        Invoke-ChildScript -Tool $updater -NoPause
    }
    finally {
        Remove-Item Env:\CULLEWIE_NVIDIA_GPU_NAME -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}
# Full setup runs in four stages, like FR33THY WinSux, without turning UAC off:
#   1 normal  (menu):      save GPU name, prepare DDU and Defender, queue stages 2 and 3, restart into safe mode
#   2 safe mode (RunOnce): DDU removes the NVIDIA driver, Defender settings apply, restart normally
#   3 normal  (task):      driver, NVIDIA settings, Windows tools; Services queues stage 4 and restarts
#   4 safe mode (RunOnce): Services settings apply, restart normally
$script:FullSetupTask = 'cullewie-full-setup'
function Invoke-RequiredTool {
    param([Parameter(Mandatory=$true)][string]$Id, [string[]]$Arguments = @())
    $tool = $script:Tools | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($Arguments.Count) { Invoke-ChildScript -Tool $tool -Arguments $Arguments -NoPause }
    else { Invoke-ChildScript -Tool $tool -NoPause }
    if ($script:LastChildExitCode -ne 0) {
        throw "$($tool.Name) did not complete. Full setup stopped."
    }
}
function Start-FullSetup {
    $statePath = Join-Path $script:RepoRoot 'nvidia-setup-state.json'
    $dduFlag = Join-Path $env:SystemRoot 'Temp\cullewie-ddu.flag'
    Remove-Item -LiteralPath $statePath, $dduFlag -Force -ErrorAction SilentlyContinue

    $nvidiaDriver = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -like 'PCI\VEN_10DE&*' -and $_.DriverProviderName -match 'NVIDIA' } |
        Select-Object -First 1
    if ($nvidiaDriver) {
        if ([string]::IsNullOrWhiteSpace([string]$nvidiaDriver.DeviceName)) {
            throw 'Could not save the NVIDIA model name before DDU cleanup.'
        }
        [IO.File]::WriteAllText($statePath, ([pscustomobject]@{ GpuName = [string]$nvidiaDriver.DeviceName } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        Write-Host "NVIDIA driver found for $($nvidiaDriver.DeviceName). DDU will remove it in safe mode." -ForegroundColor Yellow
        Invoke-RequiredTool -Id 'ddu' -Arguments '-PrepareOnly'
        [IO.File]::WriteAllText($dduFlag, '')
    }
    Invoke-RequiredTool -Id 'defender' -Arguments '-QueueOnly'

    # safe mode has no Windows Hello PIN; show the password option at sign-in (as WinSux does)
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord

    # stage 2: one safe-mode script runs DDU and Defender in order, then always leaves safe mode
    $safeScript = Join-Path $env:SystemRoot 'Temp\cullewie-safe.ps1'
    [IO.File]::WriteAllText($safeScript, @'
try {
    $flag = "$env:SystemRoot\Temp\cullewie-ddu.flag"
    if (Test-Path $flag) {
        Write-Host 'DDU: removing the NVIDIA driver' -ForegroundColor Yellow
        Start-Process -FilePath "$env:SystemRoot\Temp\ddu\Display Driver Uninstaller.exe" -ArgumentList '-Silent -NoSafeModeMsg -NoRestorePoint -CleanNvidia -RemovePhysx -RemoveGFE -RemoveNVBROADCAST -RemoveNVCP -RemoveVulkan -RemoveNvidiaDirs -Remove3DTVPlay' -Wait
        Remove-Item $flag -Force
    }
    if (Test-Path "$env:SystemRoot\Temp\defenderoptimize.ps1") {
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$env:SystemRoot\Temp\defenderoptimize.ps1"
    }
}
finally {
    cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"
    Write-Host 'Restarting' -ForegroundColor Red
    shutdown -r -t 5
}
'@, [Text.UTF8Encoding]::new($false))
    $runOnce = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    Set-ItemProperty -Path $runOnce -Name '*cullewiesafe' -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File `"$safeScript`""

    # stage 3: an elevated logon task, so no UAC prompt and UAC stays on; Task Scheduler does not run in safe mode
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $script:PowerShellExe -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ResumeFullSetup"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $script:FullSetupTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    cmd /c "bcdedit /set {current} safeboot minimal >nul 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Unregister-ScheduledTask -TaskName $script:FullSetupTask -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $runOnce -Name '*cullewiesafe' -ErrorAction SilentlyContinue
        throw 'Could not turn on safe boot. Full setup stopped.'
    }
    Write-Host 'Restarting into safe mode. Sign in after each restart; setup continues by itself.' -ForegroundColor Cyan
    shutdown -r -t 5
    exit
}
function Resume-FullSetup {
    # remove the task first so a failed step never loops on every logon
    Unregister-ScheduledTask -TaskName $script:FullSetupTask -Confirm:$false -ErrorAction SilentlyContinue
    $statePath = Join-Path $script:RepoRoot 'nvidia-setup-state.json'
    $failed = New-Object System.Collections.Generic.List[string]
    $hasNvidia = @(Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE&*' }).Count -gt 0
    if ($hasNvidia) {
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $env:CULLEWIE_NVIDIA_GPU_NAME = [string](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).GpuName
        }
        # a failed NVIDIA step must not block the Windows steps after it
        try {
            Invoke-RequiredTool -Id 'nvidia-updater'
            Invoke-RequiredTool -Id 'settings-github'
            Invoke-RequiredTool -Id 'p0-state'
        }
        catch { $failed.Add($_.Exception.Message) }
        finally {
            Remove-Item Env:\CULLEWIE_NVIDIA_GPU_NAME -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host 'No NVIDIA GPU found. Skipping the NVIDIA steps.' -ForegroundColor Cyan
    }
    foreach ($id in 'widgets', 'copilot-off', 'power-plan', 'timer-resolution', 'tweaks') {
        try { Invoke-RequiredTool -Id $id } catch { $failed.Add($_.Exception.Message) }
    }
    if ($failed.Count) {
        Write-Host ([Environment]::NewLine + 'These steps did not complete:') -ForegroundColor Red
        $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        [void](Read-Host 'Press Enter to continue with Services and the restart')
    }
    # Services goes last: it queues stage 4 in safe mode and restarts.
    Invoke-RequiredTool -Id 'services'
}
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw 'Windows PowerShell 5.1 or newer is required.'
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    throw 'Run this toolkit from 64-bit PowerShell on 64-bit Windows.'
}
if (-not (Test-IsAdministrator)) {
    Write-Host 'Run Launcher.bat or IWR.ps1 from an elevated Administrator PowerShell window.' -ForegroundColor Red
    return
}
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10 -or $osVersion.Build -lt 22000) {
    throw 'This release requires Windows 11 (build 22000 or newer).'
}
if ($ResumeFullSetup) {
    try { Resume-FullSetup }
    catch {
        Write-Host "Full setup stopped: $($_.Exception.Message)" -ForegroundColor Red
        [void](Read-Host 'Press Enter to open the launcher menu')
    }
}
while ($true) {
    Clear-Host
    Write-Host 'cullewie-s-progress — Windows setup toolkit' -ForegroundColor Cyan
    Write-Host 'Choose a script from a category to open it.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '1. Full automatic setup'
    Write-Host '2. Guided NVIDIA setup'
    Write-Host '3. Driver tools'
    Write-Host '4. NVIDIA utilities'
    Write-Host '5. Windows options'
    Write-Host '6. Digital Vibrance'
    Write-Host '0. Exit'
    $selection = Read-Host 'Choose an option'
    switch ($selection) {
        '1' {
            try { Start-FullSetup }
            catch {
                Write-Host "Full setup stopped: $($_.Exception.Message)" -ForegroundColor Red
                [void](Read-Host 'Press Enter to return to the launcher')
            }
        }
        '2' {
            try { Start-GuidedNvidiaSetup }
            catch {
                Write-Host "Guided NVIDIA setup stopped: $($_.Exception.Message)" -ForegroundColor Red
                [void](Read-Host 'Press Enter to return to the launcher')
            }
        }
        '3' { Show-ToolMenu -Category 'Drivers' }
        '4' { Show-ToolMenu -Category 'NVIDIA' }
        '5' { Show-ToolMenu -Category 'Windows' }
        '6' {
            $tool = $script:Tools | Where-Object { $_.Id -eq 'digital-vibrance' } | Select-Object -First 1
            Invoke-ChildScript -Tool $tool
        }
        '0' { return }
        default { Write-Host 'Invalid choice.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
