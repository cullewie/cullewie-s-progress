[CmdletBinding()]
param()
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
    [pscustomobject]@{ Id='widgets'; Name='Widgets Off'; Category='Windows'; Path='Scripts/Windows/Widgets.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='services'; Name='Services Off'; Category='Windows'; Path='Scripts/Windows/Services.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='power-plan'; Name='Power Plan On'; Category='Windows'; Path='Scripts/Windows/Power-Plan.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='copilot-off'; Name='Copilot Off'; Category='Windows'; Path='Scripts/Windows/Copilot-Off.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='timer-resolution'; Name='Timer Resolution On'; Category='Windows'; Path='Scripts/Windows/Timer-Resolution.ps1'; Wrapper='' }
    [pscustomobject]@{ Id='tweaks'; Name='Windows Tweaks'; Category='Windows'; Path='Scripts/Windows/Tweaks.ps1'; Wrapper='' }
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
function Start-FullSetup {
    Start-GuidedNvidiaSetup
    if ($script:LastChildExitCode -ne 0) {
        throw 'NVIDIA driver installation did not complete. Full setup stopped before Windows changes.'
    }
    # Services goes last: it restarts the computer to apply its changes.
    foreach ($id in 'settings-github', 'widgets', 'copilot-off', 'power-plan', 'timer-resolution', 'tweaks', 'services') {
        $tool = $script:Tools | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        Invoke-ChildScript -Tool $tool -NoPause
        if ($script:LastChildExitCode -ne 0) {
            throw "$($tool.Name) did not complete. Full setup stopped."
        }
    }
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
