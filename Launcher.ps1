[CmdletBinding()]
param(
    # full: the full automatic setup. guided: DDU and NVIDIA driver only, no restart (for testing on a running PC).
    # live: every step in normal Windows, no safe mode and no restart (no DDU, no Defender, no questions); restart later.
    [ValidateSet('full', 'guided', 'live')][string]$Mode = 'full',
    # Set by the full setup logon task after the first safe-mode restart.
    [switch]$ResumeFullSetup
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:RepoRoot = $PSScriptRoot
$script:PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$script:CaptureChildOutput = $false
$script:Tools = @(
    [pscustomobject]@{ Id='nvidia-updater'; Name='NVIDIA Driver'; Category='NVIDIA'; Path='Scripts/NVIDIA/Driver.ps1'; Wrapper='NvidiaCase' }
    [pscustomobject]@{ Id='ddu'; Name='DDU (driver cleanup)'; Category='GPU'; Path='Scripts/GPU/DDU.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='settings-github'; Name='NVIDIA Settings (profile, P0, refresh rate)'; Category='NVIDIA'; Path='Scripts/NVIDIA/Settings.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='amd-updater'; Name='AMD Driver'; Category='AMD'; Path='Scripts/AMD/Driver.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='amd-settings'; Name='AMD Settings (Adrenalin, refresh rate)'; Category='AMD'; Path='Scripts/AMD/Settings.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='services'; Name='Services Off'; Category='Windows'; Path='Scripts/Windows/Services.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='power-plan'; Name='Power Plan On'; Category='Windows'; Path='Scripts/Windows/Power-Plan.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='timer-resolution'; Name='Timer Resolution On'; Category='Windows'; Path='Scripts/Windows/Timer-Resolution.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='tweaks'; Name='Windows Tweaks (apps, widgets, Copilot, settings)'; Category='Windows'; Path='Scripts/Windows/Tweaks.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='defender'; Name='Defender Optimize'; Category='Windows'; Path='Scripts/Windows/Defender.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='refresh-rate'; Name='Highest Refresh Rate'; Category='GPU'; Path='Scripts/GPU/Refresh-Rate.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='display-options'; Name='Display: full-screen scaling and vibrance'; Category='GPU'; Path='Scripts/GPU/Display-Options.ps1'; Wrapper='' }
)
function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Invoke-ChildScript {
    param(
        [Parameter(Mandatory=$true)]$Tool,
        [string[]]$Arguments = @()
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
        # live mode asks nothing, so the child's lines can go through Out-Host and into the live-setup log.
        # Not otherwise: a piped child may show its questions late.
        if ($script:CaptureChildOutput) { & $script:PowerShellExe @childArguments | Out-Host }
        else { & $script:PowerShellExe @childArguments }
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
        Invoke-ChildScript -Tool $ddu -Arguments @('-GuidedNvidia')
        if ($script:LastChildExitCode -ne 0) {
            throw 'DDU did not complete. NVIDIA installation was stopped.'
        }
    }
    else {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        Write-Host 'No installed NVIDIA display driver was detected. Skipping DDU.' -ForegroundColor Cyan
        $resolved = Resolve-NvidiaGpuName
        if ($resolved) {
            [IO.File]::WriteAllText($statePath, ([pscustomobject]@{ GpuName = $resolved } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        }
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
        Invoke-ChildScript -Tool $updater
    }
    finally {
        Remove-Item Env:\CULLEWIE_NVIDIA_GPU_NAME -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}
# Full setup runs in four stages, without turning UAC off:
#   1 normal  (menu):      save GPU name, prepare DDU and Defender, queue stages 2 and 3, restart into safe mode
#   2 safe mode (RunOnce): DDU removes the NVIDIA driver, Defender settings apply, restart normally
#   3 normal  (task):      driver, NVIDIA settings, Windows tools; Services queues stage 4 and restarts
#   4 safe mode (RunOnce): Services settings apply, restart normally
$script:FullSetupTask = 'cullewie-full-setup'
function Get-NvidiaNameCandidates {
    # pci.ids name -> NVIDIA catalog names, e.g. "AD106M [GeForce RTX 4070 Max-Q / Mobile]" -> "GeForce RTX 4070 Laptop GPU"
    param([string]$PciName)
    if ($PciName -notmatch '^(\S+).*?\[(.+)\]') { return @() }
    $chip = $Matches[1]
    $name = $Matches[2]
    $laptop = $chip -match 'M$' -or $name -match 'Mobile|Max-Q|Laptop GPU'
    $name = ($name -split ' / ')[0]
    $name = $name -replace '\s+(Max-Q|Mobile|Laptop GPU|Lite Hash Rate|Engineering Sample|Refresh|GDDR6X|OEM|Rev\.\s*\S+|\d+\s?GB)\b', ''
    $name = ($name -replace '\s+', ' ').Trim()
    if ($laptop) { return @("$name Laptop GPU", $name) }
    return @($name)
}
function Get-PciGpu {
    # PCI display-class devices (class code 03) of one vendor: found even with no driver, when Windows
    # may not list the card as a video controller. Skips the card's HD audio function (class 04).
    param([Parameter(Mandatory=$true)][string]$VendorId)
    @(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'PCI\\VEN_$VendorId%'" |
        Where-Object { @($_.CompatibleID) -match '^PCI\\CC_03' })
}
function Resolve-NvidiaGpuName {
    # Without an NVIDIA driver Windows names the card "Microsoft Basic Display Adapter";
    # look the PCI device ID up in pci.ids and pick the name NVIDIA's catalog uses.
    $gpu = Get-PciGpu '10DE' | Select-Object -First 1
    if (-not $gpu) { return $null }
    if ($gpu.Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX') { return [string]$gpu.Name }
    if ($gpu.PNPDeviceID -notmatch 'DEV_([0-9A-F]{4})') { return $null }
    $deviceId = $Matches[1].ToLowerInvariant()
    try {
        $content = (Invoke-WebRequest -Uri 'https://pci-ids.ucw.cz/v2.2/pci.ids' -UseBasicParsing -TimeoutSec 60).Content
        if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
        $pciIds = $content -split "`n"
        $products = (Invoke-RestMethod -Uri 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3' -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -UseBasicParsing -TimeoutSec 60).LookupValueSearch.LookupValues.LookupValue |
            ForEach-Object { [string]$_.Name -replace '^NVIDIA\s+', '' }
    }
    catch { return $null }
    $inVendor = $false
    foreach ($line in $pciIds) {
        if ($line -match '^10de\s') { $inVendor = $true; continue }
        if ($inVendor -and $line -match '^[0-9a-f]{4}\s') { break }
        if ($inVendor -and $line -match "^\t$deviceId  (.+?)\s*$") {
            return Get-NvidiaNameCandidates $Matches[1] | Where-Object { $products -contains $_ } | Select-Object -First 1
        }
    }
    return $null
}
function Wait-Internet {
    # the logon task can start before the network is up
    for ($i = 0; $i -lt 60; $i++) {
        try { Invoke-WebRequest -Uri 'https://www.nvidia.com' -Method Head -UseBasicParsing -TimeoutSec 5 | Out-Null; return }
        catch { Start-Sleep -Seconds 5 }
    }
    throw 'No internet connection after 5 minutes.'
}
function Invoke-RequiredTool {
    param([Parameter(Mandatory=$true)][string]$Id, [string[]]$Arguments = @())
    $tool = $script:Tools | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($Arguments.Count) { Invoke-ChildScript -Tool $tool -Arguments $Arguments }
    else { Invoke-ChildScript -Tool $tool }
    if ($script:LastChildExitCode -ne 0) {
        throw "$($tool.Name) did not complete. Full setup stopped."
    }
}
function Start-FullSetup {
    # pending updates would be applied at the safe-mode boot, fail there and get rolled back
    if (Test-PendingReboot) {
        throw 'Windows is waiting for a restart to finish updates. Restart Windows normally once, then run the setup again.'
    }
    $statePath = Join-Path $script:RepoRoot 'nvidia-setup-state.json'
    $dduFlag = Join-Path $env:ProgramData 'Cullewie\Work\cullewie-ddu.flag'
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
        [IO.File]::WriteAllText($dduFlag, 'nvidia')
    }
    else {
        # remove an AMD driver only when the updater already knows the replacement:
        # a supported discrete RX 5000-9000 card, no NVIDIA card, and a live download link (saved for stage 3)
        $amdDriver = Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -like 'PCI\VEN_1002&*' -and $_.DriverProviderName -match 'Advanced Micro Devices' } | Select-Object -First 1
        if ($amdDriver) {
            $amd = $script:Tools | Where-Object { $_.Id -eq 'amd-updater' } | Select-Object -First 1
            Invoke-ChildScript -Tool $amd -Arguments @('-Resolve')
            if ($script:LastChildExitCode -eq 0) {
                Write-Host "AMD driver found for $($amdDriver.DeviceName). DDU will remove it in safe mode." -ForegroundColor Yellow
                Invoke-RequiredTool -Id 'ddu' -Arguments '-PrepareOnly'
                [IO.File]::WriteAllText($dduFlag, 'amd')
            }
            else { Write-Host 'The installed AMD driver is kept.' -ForegroundColor Cyan }
        }
    }
    Invoke-RequiredTool -Id 'defender' -Arguments '-QueueOnly'

    # BitLocker can ask for the recovery key when boot settings change; suspend it until Tweaks turns it off
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $bitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($bitLocker -and [string]$bitLocker.ProtectionStatus -eq 'On') {
            Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 0 | Out-Null
        }
    }
    # keep Windows Update from installing its own NVIDIA driver between DDU and the real driver
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 0 -Type DWord
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 -Type DWord

    # safe mode has no Windows Hello PIN; show the password option at sign-in
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord

    # stage 2: one safe-mode script runs DDU and Defender in order, then always leaves safe mode
    $safeScript = Join-Path $env:ProgramData 'Cullewie\Work\cullewie-safe.ps1'
    [IO.File]::WriteAllText($safeScript, @'
try {
    # leave safe mode first: if power fails or something hangs below, the next start is normal Windows
    cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"
    $flag = "$env:ProgramData\Cullewie\Work\cullewie-ddu.flag"
    if (Test-Path $flag) {
        $ddu = "$env:ProgramData\Cullewie\Work\ddu\Display Driver Uninstaller.exe"
        if ((Get-Content $flag -Raw) -match 'amd') {
            Write-Host 'DDU: removing the AMD driver' -ForegroundColor Yellow
            $arguments = '-Silent -NoSafeModeMsg -NoRestorePoint -CleanAmd -RemoveAMDDirs -RemoveCrimsonCache -RemoveAMDCP -RemoveVulkan'
        }
        else {
            Write-Host 'DDU: removing the NVIDIA driver' -ForegroundColor Yellow
            $arguments = '-Silent -NoSafeModeMsg -NoRestorePoint -CleanNvidia -RemovePhysx -RemoveGFE -RemoveNVBROADCAST -RemoveNVCP -RemoveVulkan -RemoveNvidiaDirs -Remove3DTVPlay'
        }
        $p = Start-Process -FilePath $ddu -ArgumentList $arguments -PassThru
        if (-not $p.WaitForExit(900000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Write-Host 'DDU did not finish in 15 minutes; stopped.' -ForegroundColor Red }
        Remove-Item $flag -Force
    }
    if (Test-Path "$env:ProgramData\Cullewie\Work\defenderoptimize.ps1") {
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramData\Cullewie\Work\defenderoptimize.ps1"
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
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { Wait-Internet } catch { $failed.Add($_.Exception.Message) }
    $hasNvidia = @(Get-PciGpu '10DE').Count -gt 0
    if ($hasNvidia) {
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $env:CULLEWIE_NVIDIA_GPU_NAME = [string](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).GpuName
        }
        else {
            $resolved = Resolve-NvidiaGpuName
            if ($resolved) { $env:CULLEWIE_NVIDIA_GPU_NAME = $resolved }
        }
        # a failed NVIDIA step must not block the Windows steps after it
        try {
            Invoke-RequiredTool -Id 'nvidia-updater'
            # profile and P0 state; the scaling and vibrance questions come last, after every other setting
            Invoke-RequiredTool -Id 'settings-github' -Arguments '-SkipDisplay'
        }
        catch { $failed.Add($_.Exception.Message) }
        finally {
            Remove-Item Env:\CULLEWIE_NVIDIA_GPU_NAME -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        }
    }
    elseif (@(Get-PciGpu '1002').Count) {
        # the updater itself skips integrated Radeon graphics and cards older than RX 5000
        try {
            Invoke-RequiredTool -Id 'amd-updater'
            # settings only on the card this toolkit just installed a driver for
            if (Test-Path (Join-Path $env:ProgramData 'Cullewie\Work\amd-installed.flag')) { Invoke-RequiredTool -Id 'amd-settings' }
        }
        catch { $failed.Add($_.Exception.Message) }
    }
    else {
        Write-Host 'No NVIDIA or AMD GPU found. Skipping the GPU steps.' -ForegroundColor Cyan
    }
    # the GPU driver is in: Windows Update may deliver drivers again (chipset, audio, Wi-Fi, Bluetooth)
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -ErrorAction SilentlyContinue
    # display-options asks the two questions (full-screen scaling, vibrance), so it runs last, after every other setting
    # NVIDIA Settings and AMD Settings set the highest refresh rate themselves; a PC with neither gets it here
    $windowsIds = @('power-plan', 'timer-resolution', 'tweaks', 'display-options')
    $amdSettingsRan = Test-Path (Join-Path $env:ProgramData 'Cullewie\Work\amd-installed.flag')
    if (-not $hasNvidia -and -not $amdSettingsRan) { $windowsIds = @('refresh-rate') + $windowsIds }
    foreach ($id in $windowsIds) {
        try { Invoke-RequiredTool -Id $id } catch { $failed.Add($_.Exception.Message) }
    }
    if ($failed.Count) {
        Write-Host ([Environment]::NewLine + 'These steps did not complete:') -ForegroundColor Red
        $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        [void](Read-Host 'Press Enter to continue with Services and the restart')
    }
    # Services goes last and applies in normal Windows, then a normal restart. Not in safe mode: Bloatware has just
    # queued feature changes that Windows applies at the next boot, and in safe mode they fail and get rolled back
    # ("undoing changes"), with extra restarts.
    Invoke-RequiredTool -Id 'services' -Arguments '-Live'
    Write-Host 'Setup finished. Restarting normally.' -ForegroundColor Green
    shutdown -r -t 10
}
function Test-PendingReboot {
    # Windows has updates or feature changes waiting for a restart
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path "$env:SystemRoot\WinSxS\pending.xml")
}
function Start-LiveSetup {
    # Same steps as stages 3 and 4, in normal Windows and without restarting. Skipped: DDU (cleans best in safe mode),
    # Defender (Tamper Protection undoes it outside safe mode) and Scaling and Vibrance (it asks questions).
    $log = Join-Path $env:ProgramData ('Cullewie\Work\live-setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    Start-Transcript -Path $log -Force | Out-Null
    $script:CaptureChildOutput = $true
    $steps = New-Object System.Collections.Generic.List[string]
    $hasNvidia = @(Get-PciGpu '10DE').Count -gt 0
    $ids = @()
    if ($hasNvidia) { $ids += 'nvidia-updater', 'settings-github' }
    elseif (@(Get-PciGpu '1002').Count) { $ids += 'amd-updater' }
    $ids += 'power-plan', 'timer-resolution', 'tweaks'
    foreach ($id in $ids) {
        $tool = $script:Tools | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # no questions in live mode: NVIDIA Settings leaves scaling and vibrance as they are
        if ($id -eq 'settings-github') { Invoke-ChildScript -Tool $tool -Arguments @('-SkipDisplay') }
        else { Invoke-ChildScript -Tool $tool }
        $steps.Add(('{0,-50} exit {1,3}  {2:mm\:ss}' -f $tool.Name, $script:LastChildExitCode, $sw.Elapsed))
    }
    # NVIDIA Settings and AMD Settings set the highest refresh rate themselves; a PC with neither gets it on its own.
    # Decided here, after the AMD updater has (re)written its flag.
    if (-not $hasNvidia) {
        $id = if (Test-Path (Join-Path $env:ProgramData 'Cullewie\Work\amd-installed.flag')) { 'amd-settings' } else { 'refresh-rate' }
        $tool = $script:Tools | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        Invoke-ChildScript -Tool $tool
        $steps.Add(('{0,-50} exit {1,3}' -f $tool.Name, $script:LastChildExitCode))
    }
    $tool = $script:Tools | Where-Object { $_.Id -eq 'services' } | Select-Object -First 1
    Invoke-ChildScript -Tool $tool -Arguments @('-Live')
    $steps.Add(('{0,-26} exit {1,3}' -f $tool.Name, $script:LastChildExitCode))
    Write-Host ([Environment]::NewLine + 'Live setup summary (exit 0 = done):') -ForegroundColor Cyan
    $steps | ForEach-Object { Write-Host "  $_" }
    Write-Host "Nothing was restarted. Restart Windows when you are ready; services change then. Log: $log" -ForegroundColor Yellow
    Stop-Transcript | Out-Null
}
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw 'Windows PowerShell 5.1 or newer is required.'
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    throw 'Run this toolkit from 64-bit PowerShell on 64-bit Windows.'
}
if (-not (Test-IsAdministrator)) {
    Write-Host 'Run IWR.ps1 from an elevated Administrator PowerShell window.' -ForegroundColor Red
    return
}
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10 -or $osVersion.Build -lt 22000) {
    throw 'This release requires Windows 11 (build 22000 or newer).'
}
Write-Host 'cullewie-s-progress - Windows setup toolkit' -ForegroundColor Cyan
try {
    if ($ResumeFullSetup) { Resume-FullSetup }
    elseif ($Mode -eq 'guided') {
        Start-GuidedNvidiaSetup
        Write-Host 'Guided NVIDIA setup finished. Nothing was restarted.' -ForegroundColor Green
    }
    elseif ($Mode -eq 'live') { Start-LiveSetup }
    else { Start-FullSetup }
}
catch { Write-Host "Setup stopped: $($_.Exception.Message)" -ForegroundColor Red }
[void](Read-Host 'Press Enter to close')
