# Installs the latest AMD Software (Adrenalin) driver for a discrete Radeon RX 5000-9000 card, silently.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$work = Join-Path $env:SystemRoot 'Temp\amd-driver'

function Get-AmdPackageLetter {
    # Navi 1x/2x (RX 5000/6000) use package "a", Navi 3x/4x (RX 7000/9000) use package "b";
    # integrated Radeon graphics and older cards are not handled here.
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_1002&*' }
    foreach ($g in $gpu) {
        if ($g.PNPDeviceID -notmatch 'DEV_([0-9A-F]{4})') { continue }
        $dev = $Matches[1].ToLowerInvariant()
        $content = (Invoke-WebRequest -Uri 'https://pci-ids.ucw.cz/v2.2/pci.ids' -UseBasicParsing -TimeoutSec 60).Content
        if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
        $inVendor = $false
        foreach ($line in $content -split "`n") {
            if ($line -match '^1002\s') { $inVendor = $true; continue }
            if ($inVendor -and $line -match '^[0-9a-f]{4}\s') { break }
            if ($inVendor -and $line -match "^\t$dev  (.+?)\s*$") {
                $name = $Matches[1]
                Write-Host "AMD GPU: $name"
                if ($name -match '^Navi [12]\d') { return 'a' }
                if ($name -match '^Navi [34]\d') { return 'b' }
            }
        }
    }
    return $null
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

try {
    $letter = Get-AmdPackageLetter
    if (-not $letter) { Write-Host 'No supported discrete AMD GPU (RX 5000-9000) found. Skipping.' -ForegroundColor Yellow; exit 0 }

    # the product pages list the current package; RX 6600 carries package "a", RX 7900 XTX carries "b"
    $page = if ($letter -eq 'a') { 'radeon-rx-6000-series/amd-radeon-rx-6600' } else { 'radeon-rx-7000-series/amd-radeon-rx-7900-xtx' }
    $html = (Invoke-WebRequest -Uri "https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/$page.html" -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -TimeoutSec 60).Content
    $m = [regex]::Match($html, "https://drivers\.amd\.com/drivers/whql-amd-software-adrenalin-edition-([\d.]+)-win11-$letter\.exe")
    if (-not $m.Success) { throw 'Could not find the AMD driver link on amd.com.' }
    Write-Host "Driver: $($m.Groups[1].Value)"

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $pkg = Join-Path $work 'amd-driver.exe'
    Save-File $m.Value $pkg
    $sig = Get-AuthenticodeSignature $pkg
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Advanced Micro Devices') { throw "AMD driver signature check failed: $($sig.Status) $($sig.SignerCertificate.Subject)" }

    # the package is a 7z archive; 7-Zip comes from this project's own release when it is not installed yet
    $7z = "$env:ProgramFiles\7-Zip\7z.exe"
    if (-not (Test-Path $7z)) {
        $setup7z = Join-Path $work '7zip.exe'
        Invoke-WebRequest 'https://github.com/cullewie/cullewie-s-progress/releases/download/files/7zip.exe' -UseBasicParsing -OutFile $setup7z
        if ((Get-FileHash $setup7z -Algorithm SHA256).Hash -ne '0859c524b8a63551848f0c246abddcb1d0b7b656b0fbfe879f8d85e61a9e6edd') { throw '7zip.exe SHA-256 mismatch; download stopped.' }
        Start-Process -Wait $setup7z -ArgumentList '/S'
    }
    Write-Host 'Extracting the AMD driver...'
    $files = Join-Path $work 'files'
    & $7z x $pkg "-o$files" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Extracting the AMD driver failed (7-Zip exit code $LASTEXITCODE)." }
    Remove-Item $pkg -Force

    Write-Host 'INSTALLING AMD DISPLAY DRIVER...' -ForegroundColor Cyan
    $log = Join-Path $work 'install.log'
    $setup = Start-Process -FilePath (Join-Path $files 'Bin64\Setup.exe') -ArgumentList "-INSTALL -LOG `"$log`"" -PassThru
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $setup.WaitForExit(1000)) {
        Write-Progress -Activity 'Installing AMD driver' -Status ('{0:mm\:ss} elapsed' -f $sw.Elapsed)
    }
    Write-Progress -Activity 'Installing AMD driver' -Completed
    # AMD log: ResultCode 0 = every package installed (some may want a restart)
    $result = if (Test-Path $log) { (Select-String -Path $log -Pattern 'ResultCode\s*=\s*(\d+)' | Select-Object -First 1).Matches.Groups[1].Value } else { $null }
    # no ResultCode line in the log: trust Setup's own exit code
    if (-not $result -and $setup.ExitCode -eq 0) { $result = '0' }
    if ($result -ne '0') { throw "AMD driver install failed (Setup exit code $($setup.ExitCode), ResultCode '$result'; log: $log)." }
    Remove-Item $files -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'AMD driver installed.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "AMD driver: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
