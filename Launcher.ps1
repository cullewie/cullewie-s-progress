[CmdletBinding()]
param(
    # full: the full automatic setup. guided: DDU and NVIDIA driver only, no restart (for testing on a running PC).
    # live: every step in normal Windows, no safe mode and no restart (no DDU, no Defender, no questions); restart later.
    # vanilla: undo this toolkit's Windows changes (GPU drivers and GPU settings stay); restart afterwards.
    [ValidateSet('full', 'guided', 'live', 'vanilla')][string]$Mode = 'full',
    # Set by the full setup logon task after the first safe-mode restart.
    [switch]$ResumeFullSetup,
    # store / xbox: keep Microsoft Store (and Xbox, Game Pass) working; full mode asks when this is empty, live mode never asks
    [string]$Apps = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:RepoRoot = $PSScriptRoot
# always Windows PowerShell 5.1: PowerShell 7 has no powershell.exe in $PSHOME
$script:PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$script:CaptureChildOutput = $false
$script:SuspendedBitLocker = $false
try { . (Join-Path $PSScriptRoot 'Scripts\TestLog.ps1') } catch { }   # TESTLOG
$script:TestLogOn = [bool](Get-Command Start-TestRun -ErrorAction SilentlyContinue)   # TESTLOG
# the Store/Xbox choice; a file, so it survives the safe-mode restarts of the full setup
$script:AppsFlag = Join-Path $env:ProgramData 'Cullewie\Work\apps.flag'
$script:Tools = @(
    [pscustomobject]@{ Id='nvidia-updater'; Name='NVIDIA Driver'; Category='NVIDIA'; Path='Scripts/GPU/NVIDIA/Driver.ps1'; Wrapper='NvidiaCase' }
    [pscustomobject]@{ Id='ddu'; Name='DDU (driver cleanup)'; Category='GPU'; Path='Scripts/GPU/DDU.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='settings-github'; Name='NVIDIA Settings (profile, P0, refresh rate)'; Category='NVIDIA'; Path='Scripts/GPU/NVIDIA/Settings.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='amd-updater'; Name='AMD Driver'; Category='AMD'; Path='Scripts/GPU/AMD/Driver.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='amd-settings'; Name='AMD Settings (Adrenalin, refresh rate)'; Category='AMD'; Path='Scripts/GPU/AMD/Settings.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='services'; Name='Services Off'; Category='Windows'; Path='Scripts/Windows/Services.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='power-plan'; Name='Power Plan On'; Category='Windows'; Path='Scripts/Windows/Power-Plan.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='timer-resolution'; Name='Timer Resolution On'; Category='Windows'; Path='Scripts/Windows/Timer-Resolution.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='tweaks'; Name='Windows Tweaks (apps, widgets, Copilot, settings)'; Category='Windows'; Path='Scripts/Windows/Tweaks.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='defender'; Name='Defender Optimize'; Category='Windows'; Path='Scripts/Windows/Defender.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='store-xbox'; Name='Microsoft Store / Xbox apps'; Category='Windows'; Path='Scripts/Windows/Store-Xbox.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='vanilla'; Name='Back to Windows defaults (vanilla)'; Category='Windows'; Path='Scripts/Windows/Vanilla.ps1'; Wrapper='' }
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
        $stepLog = if ($script:TestLogOn) { Get-TestStepLog $Tool.Name } else { $null }   # TESTLOG
        $stepWatch = [Diagnostics.Stopwatch]::StartNew()   # TESTLOG
        if ($stepLog -and $script:CaptureChildOutput) { & $script:PowerShellExe @childArguments | Tee-Object -FilePath $stepLog | Out-Host }   # TESTLOG
        elseif ($stepLog) {   # TESTLOG: an outer process holds the transcript and runs the child with -File as before (same exit codes, prompts still show)
            $quoted = (@($script:PowerShellExe) + $childArguments | ForEach-Object { "'" + ([string]$_ -replace "'", "''") + "'" }) -join ' '   # TESTLOG
            $wrapper = "Start-Transcript -LiteralPath '$($stepLog -replace "'", "''")' -Force | Out-Null; & $quoted; `$c = `$LASTEXITCODE; Stop-Transcript | Out-Null; exit `$c"   # TESTLOG
            & $script:PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper)))   # TESTLOG
        }   # TESTLOG
        elseif ($script:CaptureChildOutput) { & $script:PowerShellExe @childArguments | Out-Host }
        else { & $script:PowerShellExe @childArguments }
        $childExitCode = $LASTEXITCODE
        if ($script:TestLogOn) { Write-TestStep $Tool.Name $(if ($childExitCode -eq 0) { 'PASS' } else { 'FAIL' }) $childExitCode $stepWatch.Elapsed }   # TESTLOG
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
# Full setup runs in three stages, without turning UAC off:
#   1 normal  (menu):      save GPU name, prepare DDU and Defender, queue stages 2 and 3, restart into safe mode
#   2 safe mode (RunOnce): DDU removes the NVIDIA driver, Defender settings apply, restart normally
#   3 normal  (task):      driver, NVIDIA settings, Windows tools, then Services in normal Windows (-Live), restart normally
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
function ConvertTo-AppsLevel([string]$Value) {
    # anything but store / xbox (any case, spaces around) means off
    $v = ([string]$Value).Trim().ToLowerInvariant()
    if ($v -in 'store', 'xbox') { return $v }
    'off'
}
function Read-AppsChoice {
    if ($Apps) { return (ConvertTo-AppsLevel $Apps) }
    Write-Host ''
    $answer = Read-Host 'Hangisi? 1 = All-in, 2 = Only Store Mode, 3 = Xbox & Store'
    switch (([string]$answer).Trim()) { '2' { 'store' } '3' { 'xbox' } default { 'off' } }
}
function Save-AppsChoice([string]$Level) {
    Remove-Item -LiteralPath $script:AppsFlag -Force -ErrorAction SilentlyContinue
    if ($Level -ne 'off') {
        New-Item -ItemType Directory -Force -Path (Split-Path $script:AppsFlag) | Out-Null
        Set-Content -LiteralPath $script:AppsFlag -Value $Level
    }
    Write-Host "Microsoft Store / Xbox: $Level" -ForegroundColor Cyan
}
# arguments for Services and Tweaks, from the saved choice (none when off)
function Get-AppsArguments {
    if (-not (Test-Path -LiteralPath $script:AppsFlag)) { return }
    $level = ConvertTo-AppsLevel (Get-Content -LiteralPath $script:AppsFlag -Raw)
    if ($level -ne 'off') { '-Apps'; $level }
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
    # ask once, now: the rest of the setup runs by itself (an earlier run's answer is dropped first)
    Remove-Item -LiteralPath $script:AppsFlag -Force -ErrorAction SilentlyContinue
    $level = Read-AppsChoice
    Save-AppsChoice $level
    if ($script:TestLogOn) { [void](Start-TestRun "full-$level") }   # TESTLOG
    $statePath = Join-Path $script:RepoRoot 'nvidia-setup-state.json'
    $dduFlag = Join-Path $env:ProgramData 'Cullewie\Work\cullewie-ddu.flag'
    # also the AMD state an aborted run may have left (its saved link could install an older driver)
    Remove-Item -LiteralPath $statePath, $dduFlag, (Join-Path $env:ProgramData 'Cullewie\Work\amd-driver.json') -Force -ErrorAction SilentlyContinue

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

    # any error from here on undoes the preparation (catch below), so nothing stays half-set
    try {
    # BitLocker can ask for the recovery key when boot settings change; suspend it until Tweaks turns it off
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $bitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($bitLocker -and [string]$bitLocker.ProtectionStatus -eq 'On') {
            Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 0 | Out-Null
            $script:SuspendedBitLocker = $true
        }
    }
    # keep Windows Update from installing its own NVIDIA driver between DDU and the real driver
    # (New-Item -Force on an existing key would wipe its other values and subkeys, so create only when missing)
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device') {
        if (-not (Test-Path $key)) { New-Item -Path $key | Out-Null }
    }
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 0 -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 -Type DWord

    # safe mode has no Windows Hello PIN; show the password option at sign-in
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord

    # stage 2: one safe-mode script runs DDU and Defender in order, then always leaves safe mode
    $safeScript = Join-Path $env:ProgramData 'Cullewie\Work\cullewie-safe.ps1'
    [IO.File]::WriteAllText($safeScript, (@'
try { . '__TESTLOG__' } catch { }   # TESTLOG
$tlOn = [bool](Get-Command Write-TestStep -ErrorAction SilentlyContinue)   # TESTLOG
if ($tlOn) { Save-BootEvents; $tl = Get-TestStepLog 'safe-mode'; if ($tl) { Start-Transcript -LiteralPath $tl -Force | Out-Null } }   # TESTLOG
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
        $dduWatch = [Diagnostics.Stopwatch]::StartNew()   # TESTLOG
        $p = Start-Process -FilePath $ddu -ArgumentList $arguments -PassThru
        if (-not $p.WaitForExit(900000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Write-Host 'DDU did not finish in 15 minutes; stopped.' -ForegroundColor Red; if ($tlOn) { Write-TestStep 'DDU' 'FAIL' -1 $dduWatch.Elapsed } }   # TESTLOG: Write-TestStep
        elseif ($tlOn) { Write-TestStep 'DDU' 'PASS' $p.ExitCode $dduWatch.Elapsed }   # TESTLOG
        Remove-Item $flag -Force
    }
    if (Test-Path "$env:ProgramData\Cullewie\Work\defenderoptimize.ps1") {
        $defWatch = [Diagnostics.Stopwatch]::StartNew()   # TESTLOG
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramData\Cullewie\Work\defenderoptimize.ps1"
        if ($tlOn) { Write-TestStep 'Defender (safe mode)' $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }) $LASTEXITCODE $defWatch.Elapsed }   # TESTLOG
    }
}
finally {
    cmd /c "bcdedit /deletevalue {current} safeboot >nul 2>&1"
    if ($tlOn) { Write-TestStep 'Restart' 'INFO'; Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }   # TESTLOG
    Write-Host 'Restarting' -ForegroundColor Red
    shutdown -r -t 5
}
'@).Replace('__TESTLOG__', (Join-Path $script:RepoRoot 'Scripts\TestLog.ps1')), [Text.UTF8Encoding]::new($false))   # TESTLOG: Replace
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
    if ($LASTEXITCODE -ne 0) { throw 'Could not turn on safe boot. Full setup stopped.' }
    }
    catch {
        # undo what matters if setup never continues: the resume task and RunOnce entry, the WU driver block,
        # the DDU flag, and the BitLocker suspension (no time limit) when this run suspended it
        Unregister-ScheduledTask -TaskName $script:FullSetupTask -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '*cullewiesafe' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$env:ProgramData\Cullewie\Work\cullewie-ddu.flag" -Force -ErrorAction SilentlyContinue
        if ($script:SuspendedBitLocker -and (Get-Command Resume-BitLocker -ErrorAction SilentlyContinue)) {
            Resume-BitLocker -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
    Write-Host 'Restarting into safe mode. Sign in after each restart; setup continues by itself.' -ForegroundColor Cyan
    if ($script:TestLogOn) { Write-TestStep 'Restart (safe mode)' 'INFO' }   # TESTLOG
    shutdown -r -t 5
    exit
}
function Resume-FullSetup {
    # remove the task first so a failed step never loops on every logon
    Unregister-ScheduledTask -TaskName $script:FullSetupTask -Confirm:$false -ErrorAction SilentlyContinue
    if ($script:TestLogOn) { Save-BootEvents; Write-TestStep 'resume' 'INFO' }   # TESTLOG
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
    # Store / Xbox chosen: install the missing apps right after Tweaks (the step switches on the services it needs itself)
    if (@(Get-AppsArguments).Count) { $windowsIds = @($windowsIds | ForEach-Object { $_; if ($_ -eq 'tweaks') { 'store-xbox' } }) }
    foreach ($id in $windowsIds) {
        $toolArguments = @()
        if ($id -in 'tweaks', 'store-xbox') { $toolArguments = @(Get-AppsArguments) }
        try { Invoke-RequiredTool -Id $id -Arguments $toolArguments } catch { $failed.Add($_.Exception.Message) }
    }
    if ($failed.Count) {
        Write-Host ([Environment]::NewLine + 'These steps did not complete:') -ForegroundColor Red
        $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        [void](Read-Host 'Press Enter to continue with Services and the restart')
    }
    # Services goes last and applies in normal Windows, then a normal restart. Not in safe mode: Bloatware has just
    # queued feature changes that Windows applies at the next boot, and in safe mode they fail and get rolled back
    # ("undoing changes"), with extra restarts.
    # a Services problem (e.g. a TrustedInstaller step skipped because Windows was busy) must not cancel the restart:
    # the list itself is already imported as admin, and the restart is what applies it
    try { Invoke-RequiredTool -Id 'services' -Arguments (@('-Live') + @(Get-AppsArguments)) }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Services reported a problem (see above); restarting anyway.' -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }
    Write-Host 'Setup finished. Restarting normally.' -ForegroundColor Green
    if ($script:TestLogOn) { Write-TestStep 'Restart' 'INFO' }   # TESTLOG
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
    $log = Join-Path $env:ProgramData ('User\Work\live-setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    Start-Transcript -Path $log -Force | Out-Null
    $script:CaptureChildOutput = $true
    # no question in live mode: the Store/Xbox level comes from -Apps (IWR: CULLEWIE_APPS); empty or unknown = off
    Save-AppsChoice (ConvertTo-AppsLevel $Apps)
    if ($script:TestLogOn) { [void](Start-TestRun "live-$(ConvertTo-AppsLevel $Apps)") }   # TESTLOG
    # (the flag file $script:AppsFlag now holds the level for Get-AppsArguments)
    $steps = New-Object System.Collections.Generic.List[string]
    $hasNvidia = @(Get-PciGpu '10DE').Count -gt 0
    $ids = @()
    if ($hasNvidia) { $ids += 'nvidia-updater', 'settings-github' }
    elseif (@(Get-PciGpu '1002').Count) { $ids += 'amd-updater' }
    $ids += 'power-plan', 'timer-resolution', 'tweaks'
    if (@(Get-AppsArguments).Count) { $ids += 'store-xbox' }
    foreach ($id in $ids) {
        $tool = $script:Tools | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # no questions in live mode: NVIDIA Settings leaves scaling and vibrance as they are
        if ($id -eq 'settings-github') { Invoke-ChildScript -Tool $tool -Arguments @('-SkipDisplay') }
        elseif ($id -in 'tweaks', 'store-xbox') { Invoke-ChildScript -Tool $tool -Arguments @(Get-AppsArguments) }
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
    Invoke-ChildScript -Tool $tool -Arguments (@('-Live') + @(Get-AppsArguments))
    $steps.Add(('{0,-50} exit {1,3}' -f $tool.Name, $script:LastChildExitCode))
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
        if ($script:TestLogOn) { [void](Start-TestRun 'guided') }   # TESTLOG
        Start-GuidedNvidiaSetup
        Write-Host 'Guided NVIDIA setup finished. Nothing was restarted.' -ForegroundColor Green
    }
    elseif ($Mode -eq 'live') { Start-LiveSetup }
    elseif ($Mode -eq 'vanilla') {
        # no question and no restart here: the script lists what it could not undo, the user restarts
        if ($script:TestLogOn) { [void](Start-TestRun 'vanilla') }   # TESTLOG
        Invoke-RequiredTool -Id 'vanilla'
        Write-Host 'Back to Windows defaults. Restart Windows now to finish.' -ForegroundColor Green
    }
    else { Start-FullSetup }
}
catch { Write-Host "Setup stopped: $($_.Exception.Message)" -ForegroundColor Red }
[void](Read-Host 'Press Enter to close')
