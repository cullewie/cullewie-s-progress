# Store / Xbox apps: with -Apps store, installs Microsoft Store if it is missing; with -Apps xbox also the Xbox app,
# Gaming Services, Xbox Identity Provider and the Game Bar. Works right away, without a restart: the services an
# install needs are switched on through the service manager (sc.exe), which applies at once (a registry write would
# wait for the next restart). Services.ps1 -Apps writes the same start types for later boots.
# Exit 0 = every package for the level is installed; 1 = something is missing (listed).
param([Parameter(Mandatory = $true)][ValidateSet('store', 'xbox')][string]$Apps)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Store installs go through Windows Update, BITS, Delivery Optimization, the Store install and licence services
$installServices = [ordered]@{ wuauserv = 'demand'; BITS = 'demand'; DoSvc = 'demand'; InstallService = 'demand'; ClipSVC = 'demand'; LicenseManager = 'demand'; AppXSvc = 'demand' }
if ($Apps -eq 'xbox') {
    # Xbox sign-in, cloud saves, networking (needs IKEEXT, Teredo via iphlpsvc), GameInput, Bluetooth controller pairing,
    # and the controller drivers (xboxgip: wired/adapter, xinputhid: Bluetooth)
    foreach ($name in 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc', 'IKEEXT', 'GameInputSvc', 'bthserv', 'DeviceAssociationService', 'xboxgip', 'xinputhid') { $installServices[$name] = 'demand' }
    $installServices['iphlpsvc'] = 'auto'
}
# Microsoft Store product IDs (winget source "msstore") and the package each one installs
$packages = [ordered]@{ '9WZDNCRFJBMP' = 'Microsoft.WindowsStore' }
if ($Apps -eq 'xbox') {
    $packages['9WZDNCRD1HKW'] = 'Microsoft.XboxIdentityProvider'
    $packages['9MWPM2CQNLHN'] = 'Microsoft.GamingServices'
    $packages['9MV0B5HZVK9Z'] = 'Microsoft.GamingApp'
    $packages['9NZKPSTSNW4P'] = 'Microsoft.XboxGamingOverlay'
}
function Test-Package([string]$Name) { [bool](Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue) }

Write-Host "Store / Xbox ($Apps): services for installs"
foreach ($name in $installServices.Keys) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Host "  $name is missing" -ForegroundColor Yellow; continue }
    if ($svc.StartType -eq 'Disabled') { sc.exe config $name start= $($installServices[$name]) | Out-Null }
}
foreach ($name in 'wuauserv', 'BITS') { Start-Service -Name $name -ErrorAction SilentlyContinue }
if ($Apps -eq 'xbox') {
    Start-Service -Name 'iphlpsvc' -ErrorAction SilentlyContinue
    # Teredo carries Xbox party chat and multiplayer NAT. "enterpriseclient": the plain client stays offline with
    # "client is in a managed network" on many home routers (Xbox's own "Teredo is unable to qualify" fix)
    Write-Host '  Teredo: enterprise client'
    netsh interface teredo set state type=enterpriseclient | Out-Null
}

# one winget run with a time limit: a Store install can wait forever (2026-11-23: the Game Bar, 8+ minutes, twice).
# Its lines are printed when it ends; returns its exit code, -1 when it was stopped.
function Invoke-Winget([string]$Exe, [string[]]$Arguments, [int]$TimeoutSeconds = 900) {
    $out = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $out
    $null = $p.Handle
    $finished = $p.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    # winget's spinner and progress bar lines are left out
    Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Where-Object { $_ -match '[A-Za-z]{2}' } | ForEach-Object { Write-Host $_ }
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    if (-not $finished) { Write-Host "  winget did not finish in $([int]($TimeoutSeconds / 60)) minutes; stopped" -ForegroundColor Yellow; return -1 }
    $p.ExitCode
}

# All-in locks winget with its policy and removes App Installer (Tweaks.ps1); every install below needs it back
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller' -Name 'EnableAppInstaller' -ErrorAction SilentlyContinue
function Restore-AppInstaller {
    if (Test-Package 'Microsoft.DesktopAppInstaller') { return }
    Write-Host '  installing App Installer (winget) ...'
    # the EndOfLife and Deprovisioned entries All-in wrote block it, so they go first
    $appxStore = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
    $family = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    Get-ChildItem "$appxStore\EndOfLife" -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Microsoft.DesktopAppInstaller_*' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "$appxStore\Deprovisioned\$family" -Recurse -Force -ErrorAction SilentlyContinue
    # Windows' own copy, while its files are still on the disk
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage $family -ErrorAction Stop } catch { }
    if (Test-Package 'Microsoft.DesktopAppInstaller') { return }
    # otherwise Microsoft's winget release (signed packages: Windows checks the signature when it installs them)
    $dir = Join-Path $env:TEMP 'cullewie-appinstaller'
    try {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $dir | Out-Null
        $release = 'https://github.com/microsoft/winget-cli/releases/latest/download/'
        Invoke-WebRequest ($release + "$family.msixbundle") -OutFile "$dir\AppInstaller.msixbundle" -UseBasicParsing
        Invoke-WebRequest ($release + 'DesktopAppInstaller_Dependencies.zip') -OutFile "$dir\deps.zip" -UseBasicParsing
        Expand-Archive "$dir\deps.zip" "$dir\deps" -Force
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $deps = @(Get-ChildItem "$dir\deps" -Recurse -Include *.appx, *.msix | Where-Object { $_.Directory.Name -eq $arch } | ForEach-Object { $_.FullName })
        Add-AppxPackage -Path "$dir\AppInstaller.msixbundle" -DependencyPath $deps -ForceApplicationShutdown -ErrorAction Stop
    }
    catch { Write-Host "  App Installer: $($_.Exception.Message)" -ForegroundColor Yellow }
    finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
}
Restore-AppInstaller
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
foreach ($id in $packages.Keys) {
    $name = $packages[$id]
    if (Test-Package $name) { Write-Host "  $name already installed"; continue }
    Write-Host "  installing $name ..."
    if ($winget) {
        [void](Invoke-Winget $winget.Source @('install', '--id', $id, '--source', 'msstore', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'))
    }
    # the Store itself has a built-in reinstall when winget could not do it
    if ($name -eq 'Microsoft.WindowsStore' -and -not (Test-Package $name)) {
        Start-Process wsreset.exe -ArgumentList '-i' -WindowStyle Hidden
        $deadline = (Get-Date).AddMinutes(5)
        while (-not (Test-Package $name) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
    }
}

# GameInput (needed by many Game Pass games) is a normal program, not a Store package
$gameInputMissing = $false
if ($Apps -eq 'xbox') {
    $uninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $hasGameInput = { [bool](Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName -like '*Microsoft GameInput*' }) }
    if (-not (& $hasGameInput) -and $winget) {
        Write-Host '  installing Microsoft GameInput ...'
        [void](Invoke-Winget $winget.Source @('install', '--id', 'Microsoft.GameInput', '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'))
    }
    $gameInputMissing = -not (& $hasGameInput)
}

$missing = @($packages.Values | Where-Object { -not (Test-Package $_) }) + @(if ($gameInputMissing) { 'Microsoft GameInput' })
if ($missing) {
    Write-Host "Store / Xbox: not installed: $($missing -join ', '). Check the internet connection and run this step again." -ForegroundColor Red
    exit 1
}
Write-Host "Store / Xbox: ready ($($packages.Values -join ', '))." -ForegroundColor Green
exit 0
