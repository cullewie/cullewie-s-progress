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
if ($Apps -eq 'xbox') { Start-Service -Name 'iphlpsvc' -ErrorAction SilentlyContinue }

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
foreach ($id in $packages.Keys) {
    $name = $packages[$id]
    if (Test-Package $name) { Write-Host "  $name already installed"; continue }
    Write-Host "  installing $name ..."
    if ($winget) {
        & $winget.Source install --id $id --source msstore --accept-package-agreements --accept-source-agreements --silent --disable-interactivity | Out-Host
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
        & $winget.Source install --id Microsoft.GameInput --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity | Out-Host
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
