# Installs the latest AMD Software (Adrenalin) driver for a discrete Radeon RX 5000-9000 card, silently.
# -Resolve (full setup, before DDU): only find the package and its link and save them; exit 0 = ready, 3 = not handled here.
param([switch]$Resolve)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$root = Join-Path $env:ProgramData 'Cullewie\Work'
$work = Join-Path $root 'amd-driver'
$state = Join-Path $root 'amd-driver.json'
$installedFlag = Join-Path $root 'amd-installed.flag'

function Get-AmdPackageLetter {
    # Navi 1x/2x (RX 5000/6000) use package "a", Navi 3x/4x (RX 7000/9000) use package "b".
    # Integrated Radeon graphics, older cards and Radeon PRO cards are not handled here.
    # PCI display class (03): found even with no driver; skips the HD audio function
    $gpus = @(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'PCI\\VEN_1002%'" | Where-Object { @($_.CompatibleID) -match '^PCI\\CC_03' })
    if (-not $gpus.Count) { return $null }
    $content = (Invoke-WebRequest -Uri 'https://pci-ids.ucw.cz/v2.2/pci.ids' -UseBasicParsing -TimeoutSec 60).Content
    if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
    $lines = $content -split "`n"
    foreach ($g in $gpus) {
        if ($g.PNPDeviceID -notmatch 'DEV_([0-9A-F]{4})') { continue }
        $dev = $Matches[1].ToLowerInvariant()
        $inVendor = $false
        foreach ($line in $lines) {
            if ($line -match '^1002\s') { $inVendor = $true; continue }
            if ($inVendor -and $line -match '^[0-9a-f]{4}\s') { break }
            if ($inVendor -and $line -match "^\t$dev  (.+?)\s*$") {
                $name = $Matches[1]
                Write-Host "AMD GPU: $name"
                if ($name -match '\bPro\b|Instinct|FirePro') { break }
                if ($name -match '^Navi [12]\d') { return 'a' }
                if ($name -match '^Navi [34]\d') { return 'b' }
                break
            }
        }
    }
    return $null
}

function Get-AmdDriverLink([string]$Letter) {
    # the product pages list the current package; RX 6600 carries package "a", RX 7900 XTX carries "b"
    $page = if ($Letter -eq 'a') { 'radeon-rx-6000-series/amd-radeon-rx-6600' } else { 'radeon-rx-7000-series/amd-radeon-rx-7900-xtx' }
    $html = (Invoke-WebRequest -Uri "https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/$page.html" -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -TimeoutSec 60).Content
    $m = [regex]::Match($html, "https://drivers\.amd\.com/drivers/whql-amd-software-adrenalin-edition-([\d.]+)-win11-$Letter\.exe")
    if (-not $m.Success) { throw 'Could not find the AMD driver link on amd.com.' }
    return [pscustomobject]@{ Letter = $Letter; Url = $m.Value; Version = $m.Groups[1].Value }
}

function Save-File([string]$Url, [string]$Path) {
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = $ua
    $req.Referer = 'https://www.amd.com/'
    $req.Timeout = 60000
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($Path)
    try {
        $buf = New-Object byte[] 1048576
        $done = 0L; $last = [DateTime]::MinValue
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $done += $n
            if (([DateTime]::Now - $last).TotalMilliseconds -gt 500) {
                $last = [DateTime]::Now
                $pct = if ($total -gt 0) { [int](100 * $done / $total) } else { 0 }
                Write-Progress -Activity 'Downloading AMD driver' -Status ('{0} / {1} MB' -f [int]($done / 1MB), [int]($total / 1MB)) -PercentComplete $pct
            }
        }
    }
    finally { $out.Close(); $in.Close(); $resp.Close(); Write-Progress -Activity 'Downloading AMD driver' -Completed }
    if ($total -gt 0 -and (Get-Item $Path).Length -ne $total) { throw 'AMD driver download is incomplete.' }
}

New-Item -ItemType Directory -Path $root -Force | Out-Null

if ($Resolve) {
    # never remove a working driver unless the new one is known: no NVIDIA card next to it, a supported Radeon, a live link
    try {
        if (@(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'PCI\\VEN_10DE%'" | Where-Object { @($_.CompatibleID) -match '^PCI\\CC_03' }).Count) { Write-Host 'NVIDIA GPU present; the AMD path is not used.'; exit 3 }
        $letter = Get-AmdPackageLetter
        if (-not $letter) { Write-Host 'No supported discrete AMD GPU (RX 5000-9000).'; exit 3 }
        $target = Get-AmdDriverLink $letter
        [IO.File]::WriteAllText($state, ($target | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
        Write-Host "AMD driver $($target.Version) found; the old driver can be removed."
        exit 0
    }
    catch { Write-Host "AMD driver: $($_.Exception.Message)" -ForegroundColor Yellow; exit 3 }
}

try {
    Remove-Item $installedFlag -Force -ErrorAction SilentlyContinue
    $target = $null
    if (Test-Path $state) { $target = Get-Content $state -Raw | ConvertFrom-Json }
    if (-not $target) {
        $letter = Get-AmdPackageLetter
        if (-not $letter) { Write-Host 'No supported discrete AMD GPU (RX 5000-9000) found. Skipping.' -ForegroundColor Yellow; exit 0 }
        $target = Get-AmdDriverLink $letter
    }
    Write-Host "Driver: $($target.Version)"

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $pkg = Join-Path $work 'amd-driver.exe'
    try { Save-File $target.Url $pkg }
    catch {
        # the saved link may have been replaced on amd.com since stage 1
        Write-Host "Saved link failed ($($_.Exception.Message)); looking up the current one." -ForegroundColor Yellow
        $target = Get-AmdDriverLink $target.Letter
        Save-File $target.Url $pkg
    }
    $sig = Get-AuthenticodeSignature $pkg
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Advanced Micro Devices') { throw "AMD driver signature check failed: $($sig.Status) $($sig.SignerCertificate.Subject)" }

    # the package is a 7z archive; 7-Zip comes from this project's own release when it is not installed yet, and is
    # removed again right after the extraction (a 7-Zip the user had stays)
    $7z = "$env:ProgramFiles\7-Zip\7z.exe"
    $had7z = Test-Path $7z
    if (-not $had7z) {
        $setup7z = Join-Path $work '7zip.exe'
        Invoke-WebRequest 'https://github.com/cullewie/cullewie-s-progress/releases/download/files/7zip.exe' -UseBasicParsing -OutFile $setup7z
        if ((Get-FileHash $setup7z -Algorithm SHA256).Hash -ne '0859c524b8a63551848f0c246abddcb1d0b7b656b0fbfe879f8d85e61a9e6edd') { throw '7zip.exe SHA-256 mismatch; download stopped.' }
        Start-Process -Wait $setup7z -ArgumentList '/S'
    }
    Write-Host 'Extracting the AMD driver...'
    $files = Join-Path $work 'files'
    & $7z x $pkg "-o$files" -y | Out-Null
    $extractCode = $LASTEXITCODE
    if (-not $had7z) { Start-Process -Wait "$env:ProgramFiles\7-Zip\Uninstall.exe" -ArgumentList '/S' -ErrorAction SilentlyContinue; Remove-Item (Join-Path $work '7zip.exe') -Force -ErrorAction SilentlyContinue }
    if ($extractCode -ne 0) { throw "Extracting the AMD driver failed (7-Zip exit code $extractCode)." }
    Remove-Item $pkg -Force

    Write-Host 'INSTALLING AMD DISPLAY DRIVER...' -ForegroundColor Cyan
    $log = Join-Path $work 'install.log'
    $setup = Start-Process -FilePath (Join-Path $files 'Bin64\Setup.exe') -ArgumentList "-INSTALL -LOG `"$log`"" -PassThru
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $setup.WaitForExit(1000)) {
        Write-Progress -Activity 'Installing AMD driver' -Status ('{0:mm\:ss} elapsed' -f $sw.Elapsed)
    }
    # Setup can hand the work to child installers; wait until none of them is left
    while (Get-Process -Name 'ATISetup', 'AMDSoftwareInstaller', 'InstallManagerApp' -ErrorAction SilentlyContinue) {
        if ($sw.Elapsed.TotalMinutes -gt 30) { break }
        Write-Progress -Activity 'Installing AMD driver' -Status ('{0:mm\:ss} elapsed' -f $sw.Elapsed)
        Start-Sleep -Seconds 2
    }
    Write-Progress -Activity 'Installing AMD driver' -Completed
    # AMD log: ResultCode 0 = every package installed (some may want a restart)
    $match = if (Test-Path $log) { Select-String -Path $log -Pattern 'ResultCode\s*=\s*(\d+)' | Select-Object -First 1 }
    $result = if ($match) { $match.Matches[0].Groups[1].Value } else { $null }
    if (-not $result -and $setup.ExitCode -eq 0) { $result = '0' }
    if ($result -ne '0') { throw "AMD driver install failed (Setup exit code $($setup.ExitCode), ResultCode '$result'; log: $log)." }

    # an AMD driver must now be bound to the Radeon card
    $bound = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -like 'PCI\VEN_1002&*' -and $_.DriverProviderName -match 'Advanced Micro Devices' }
    if (-not $bound) { throw "Setup finished, but no AMD display driver is bound to the card (log: $log)." }
    Remove-Item $files -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $state -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($installedFlag, '')
    Write-Host 'AMD driver installed.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "AMD driver: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
