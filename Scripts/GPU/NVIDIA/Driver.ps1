1 {
    Clear-Host

    $ErrorActionPreference = "Stop"
    # Keep PowerShell's download progress visible in the console.
    $ProgressPreference = "Continue"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Headers = @{
        "User-Agent" = "Mozilla/5.0"
    }

    # download / install data: printed, and (when the run log is there) one INFO line in steps.log, so the setup
    # window and the log show size, time and speed. Never stops the driver step.
    function Write-DriverData([string]$Kind, [string]$Version, [int64]$Bytes = 0, [timespan]$Elapsed = [timespan]::Zero, [int]$ExitCode = 0) {
        $time = '{0:00}:{1:00}' -f [math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds
        if ($Kind -eq 'download') {
            $speed = if ($Elapsed.TotalSeconds -gt 0) { ($Bytes / 1MB) / $Elapsed.TotalSeconds } else { 0 }
            $line = 'NVIDIA indirme: {0} - {1:N0} MB - {2} - {3} MB/s' -f $Version, ($Bytes / 1MB), $time, ([math]::Round($speed, 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            $note = if ($ExitCode -eq 1) { ' (yeniden baslatma gerekiyor)' } else { '' }
            $line = 'NVIDIA kurulum: {0} - {1} - cikis kodu {2}{3}' -f $Version, $time, $ExitCode, $note
        }
        Write-Host $line -ForegroundColor Cyan
        try { if (Get-Command Write-TestStep -ErrorAction SilentlyContinue) { Write-TestStep $line 'INFO' $ExitCode $Elapsed } } catch { }
        $line
    }
    # the run log helpers: next to Launcher.ps1 when the Launcher runs this wrapped, else two folders up
    foreach ($TestLogPath in (Join-Path $PSScriptRoot 'Scripts\TestLog.ps1'), (Join-Path $PSScriptRoot '..\..\TestLog.ps1')) {
        if (Test-Path -LiteralPath $TestLogPath) { try { . $TestLogPath } catch { }; break }
    }

    try {
        Write-Host "DETECTING NVIDIA GPU..." -ForegroundColor Yellow

        # Any PCI device from NVIDIA with display class code 03, so the card is found even with no driver
        # (then Windows lists it as "Microsoft Basic Display Adapter" or "Video Controller", or not as a video controller at all).
        # The NVIDIA HD audio function (class 04) is skipped.
        $GPUs = @(
            Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'PCI\\VEN_10DE%'" |
            Where-Object { @($_.CompatibleID) -match '^PCI\\CC_03' }
        )

        if ($GPUs.Count -ne 1) {
            throw "Expected exactly one NVIDIA GPU. Found: $($GPUs.Count)"
        }

        $GPU = $GPUs[0]
        if (-not [string]::IsNullOrWhiteSpace($env:CULLEWIE_NVIDIA_GPU_NAME)) {
            $GPU = [PSCustomObject]@{ Name = $env:CULLEWIE_NVIDIA_GPU_NAME; PNPDeviceID = $GPU.PNPDeviceID }
        }

        # NVIDIA lookup API
        $API = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID="

        $Series = (Invoke-RestMethod `
            -Uri "${API}2" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        $Products = (Invoke-RestMethod `
            -Uri "${API}3" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        # No driver: the Windows name is generic. Look the PCI device ID up in pci.ids and pick the name NVIDIA's catalog uses,
        # e.g. "GB203 [GeForce RTX 5070 Ti]" -> "GeForce RTX 5070 Ti", "AD106M [GeForce RTX 4070 Max-Q / Mobile]" -> "GeForce RTX 4070 Laptop GPU".
        if ($GPU.Name -notmatch 'NVIDIA|GeForce|Quadro|RTX|GTX|TITAN') {
            Write-Host "No NVIDIA driver name ($($GPU.Name)); looking up the PCI device ID..." -ForegroundColor Yellow
            if ($GPU.PNPDeviceID -notmatch 'DEV_([0-9A-F]{4})') { throw "Could not read the PCI device ID: $($GPU.PNPDeviceID)" }
            $DeviceId = $Matches[1].ToLowerInvariant()
            $PciIds = (Invoke-WebRequest -Uri 'https://pci-ids.ucw.cz/v2.2/pci.ids' -UseBasicParsing -TimeoutSec 60).Content
            if ($PciIds -is [byte[]]) { $PciIds = [Text.Encoding]::UTF8.GetString($PciIds) }
            $CatalogNames = @($Products | ForEach-Object { [string]$_.Name -replace '^NVIDIA\s+', '' })
            $InVendor = $false
            $Resolved = $null
            foreach ($Line in $PciIds -split "`n") {
                if ($Line -match '^10de\s') { $InVendor = $true; continue }
                if ($InVendor -and $Line -match '^[0-9a-f]{4}\s') { break }
                if ($InVendor -and $Line -match "^\t$DeviceId  (\S+).*?\[(.+)\]") {
                    $Chip = $Matches[1]
                    $Name = ($Matches[2] -split ' / ')[0]
                    $Laptop = $Chip -match 'M$' -or $Matches[2] -match 'Mobile|Max-Q|Laptop GPU'
                    $Name = $Name -replace '\s+(Max-Q|Mobile|Laptop GPU|Lite Hash Rate|Engineering Sample|Refresh|GDDR6X|OEM|Rev\.\s*\S+|\d+\s?GB)\b', ''
                    $Name = ($Name -replace '\s+', ' ').Trim()
                    $Candidates = if ($Laptop) { @("$Name Laptop GPU", $Name) } else { @($Name) }
                    $Resolved = $Candidates | Where-Object { $CatalogNames -contains $_ } | Select-Object -First 1
                    break
                }
            }
            if (!$Resolved) { throw "PCI device 10de:$DeviceId is not in NVIDIA's driver catalog." }
            $GPU = [PSCustomObject]@{ Name = $Resolved; PNPDeviceID = $GPU.PNPDeviceID }
        }

        Write-Host "GPU: $($GPU.Name)" -ForegroundColor Green

        $OSList = (Invoke-RestMethod `
            -Uri "${API}4" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        # Match GPU; NVIDIA lists many models without the "NVIDIA " prefix that Windows reports.
        $GPUShortName = $GPU.Name -replace '^NVIDIA\s+', ''
        $Product = $Products |
            Where-Object { ($_.Name -replace '^NVIDIA\s+', '') -eq $GPUShortName } |
            Select-Object -First 1

        if (!$Product) {
            throw "GPU not found in NVIDIA product database."
        }

        $GPUSeries = $Series |
            Where-Object { $_.Value -eq $Product.ParentID } |
            Select-Object -First 1

        if (!$GPUSeries) {
            throw "GPU series not found."
        }

        # Detect Windows
        $WindowsName = if ([Environment]::OSVersion.Version.Build -ge 22000) {
            "Windows 11"
        }
        else {
            "Windows 10"
        }

        $OS = $OSList |
            Where-Object { $_.Name -eq $WindowsName } |
            Select-Object -First 1

        if (!$OS) {
            throw "Windows version not found in NVIDIA database."
        }

        # NVIDIA driver lookup
        $URI = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$($Product.ParentID)&pfid=$($Product.Value)&osID=$($OS.Value)&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"

        $Response = Invoke-RestMethod `
            -Uri $URI `
            -Headers $Headers `
            -UseBasicParsing

        $DriverEntry = $Response.IDS |
            Where-Object { $_.downloadInfo.Success -eq "1" } |
            Select-Object -First 1

        if (!$DriverEntry) {
            throw "No matching NVIDIA WHQL driver found."
        }

        $Driver = $DriverEntry.downloadInfo

        if (!$Driver.DownloadURL) {
            throw "NVIDIA download URL is missing."
        }

        # Validate download source
        $DownloadUri = [Uri]$Driver.DownloadURL

        if (
            $DownloadUri.Scheme -ne "https" -or
            $DownloadUri.Host -notmatch '(^|\.)nvidia\.com$'
        ) {
            throw "Untrusted NVIDIA download URL."
        }

        # Same version already installed: nothing to download. Windows reports 32.0.16.2124 for NVIDIA 621.24
        # (the last five digits).
        $Installed = Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -like 'PCI\VEN_10DE&*' -and $_.DriverProviderName -match 'NVIDIA' } |
            Select-Object -First 1
        if ($Installed -and $Installed.DriverVersion) {
            $Digits = $Installed.DriverVersion -replace '\D', ''
            if ($Digits.Length -ge 5) {
                $InstalledVersion = $Digits.Substring($Digits.Length - 5).Insert(3, '.')
                if ($InstalledVersion -eq $Driver.Version) {
                    Write-Host "`nNVIDIA driver $InstalledVersion is already installed (latest). Skipping the download." -ForegroundColor Green
                    exit
                }
                Write-Host "Installed: $InstalledVersion -> latest: $($Driver.Version)"
            }
        }

        # Download
        $TargetPath = Join-Path "$env:ProgramData\Cullewie\Work" "nvidia-driver-$($Driver.Version).exe"

        Write-Host "`nDRIVER FOUND" -ForegroundColor Green
        Write-Host "GPU: $($GPU.Name)"
        Write-Host "Series: $($GPUSeries.Name)"
        Write-Host "Driver: $($Driver.Version)"
        Write-Host "Release: $($Driver.ReleaseDateTime)"
        Write-Host "WHQL: $($Driver.IsWHQL)"
        Write-Host "Download: $($Driver.DownloadURL)"

        Write-Host "`nDOWNLOADING NVIDIA DRIVER..." -ForegroundColor Yellow

        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Force
        }

        $DownloadRequest = [System.Net.HttpWebRequest]::Create([Uri]$Driver.DownloadURL)
        $DownloadRequest.Method = 'GET'
        $DownloadRequest.UserAgent = $Headers['User-Agent']
        $DownloadRequest.Timeout = 60000
        $DownloadRequest.ReadWriteTimeout = 60000
        $DownloadResponse = $null
        $DownloadInput = $null
        $DownloadOutput = $null
        try {
            $DownloadResponse = $DownloadRequest.GetResponse()
            $DownloadLength = [int64]$DownloadResponse.ContentLength
            $DownloadInput = $DownloadResponse.GetResponseStream()
            $DownloadOutput = [System.IO.File]::Open($TargetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $DownloadBuffer = New-Object byte[] 1048576
            $DownloadedBytes = [int64]0
            $ProgressTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $NextProgressUpdate = [int64]0
            # a plain line every 10 %: Write-Progress shows only in the console, never in the log or the setup window
            $NextReportPercent = 10

            while (($BytesRead = $DownloadInput.Read($DownloadBuffer, 0, $DownloadBuffer.Length)) -gt 0) {
                $DownloadOutput.Write($DownloadBuffer, 0, $BytesRead)
                $DownloadedBytes += $BytesRead
                if ($DownloadLength -gt 0 -and ($DownloadedBytes * 100 / $DownloadLength) -ge $NextReportPercent) {
                    Write-Host ('  indiriliyor: %{0} - {1:N0} / {2:N0} MB - {3:mm\:ss}' -f $NextReportPercent, ($DownloadedBytes / 1MB), ($DownloadLength / 1MB), $ProgressTimer.Elapsed)
                    $NextReportPercent += 10
                }
                if ($ProgressTimer.ElapsedMilliseconds -ge $NextProgressUpdate) {
                    if ($DownloadLength -gt 0) {
                        $DownloadPercent = [int][Math]::Min(99, [Math]::Floor(($DownloadedBytes * 100.0) / $DownloadLength))
                        $DownloadStatus = '{0}% - {1:N0} MB / {2:N0} MB' -f $DownloadPercent, ($DownloadedBytes / 1MB), ($DownloadLength / 1MB)
                        Write-Progress -Activity 'Downloading NVIDIA driver' -Status $DownloadStatus -PercentComplete $DownloadPercent
                    }
                    else {
                        $DownloadStatus = '{0:N0} MB downloaded - server did not provide total size' -f ($DownloadedBytes / 1MB)
                        Write-Progress -Activity 'Downloading NVIDIA driver' -Status $DownloadStatus -PercentComplete 0
                    }
                    $NextProgressUpdate = $ProgressTimer.ElapsedMilliseconds + 400
                }
            }
            $DownloadOutput.Flush()
            Write-Progress -Activity 'Downloading NVIDIA driver' -Completed
            [void](Write-DriverData -Kind 'download' -Version $Driver.Version -Bytes $DownloadedBytes -Elapsed $ProgressTimer.Elapsed)
        }
        finally {
            if ($DownloadOutput) { $DownloadOutput.Dispose() }
            if ($DownloadInput) { $DownloadInput.Dispose() }
            if ($DownloadResponse) { $DownloadResponse.Dispose() }
        }

        if (!(Test-Path $TargetPath)) {
            throw "Driver download failed."
        }

        $File = Get-Item $TargetPath

        if ($File.Length -le 0) {
            throw "Downloaded file is empty."
        }

        Write-Host "`nVERIFYING DIGITAL SIGNATURE..." -ForegroundColor Yellow

        $Signature = Get-AuthenticodeSignature -LiteralPath $TargetPath

        if ($Signature.Status -ne "Valid") {
            throw "Invalid digital signature: $($Signature.Status)"
        }

        $Signer = $Signature.SignerCertificate.Subject

        if ($Signer -notmatch "NVIDIA Corporation") {
            throw "Unexpected publisher: $Signer"
        }

        Write-Host "`nDRIVER VERIFIED" -ForegroundColor Green

        [PSCustomObject]@{
            GPU          = $GPU.Name
            Driver       = $Driver.Version
            ReleaseDate  = $Driver.ReleaseDateTime
            FileSizeMB   = [math]::Round($File.Length / 1MB, 2)
            Signature    = $Signature.Status
            Publisher    = $Signer
            File         = $TargetPath
        } | Format-List

        # Do not let Windows fetch NVIDIA Control Panel from the Store after the driver installs
        # ("download manufacturers' apps for devices" = No); with Store services off that install only fails.
        foreach ($Key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata') {
            if (-not (Test-Path $Key)) { New-Item -Path $Key | Out-Null }
            Set-ItemProperty -Path $Key -Name 'PreventDeviceMetadataFromNetwork' -Value 1 -Type DWord
        }

        Write-Host "INSTALLING NVIDIA DISPLAY DRIVER..." -ForegroundColor Green

        $Installer = Start-Process -FilePath $TargetPath -ArgumentList @('-s', '-n', 'Display.Driver') -PassThru
        $null = $Installer.Handle   # keeps ExitCode readable after a non -Wait start
        $InstallTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $NextInstallReport = 15
        while (-not $Installer.WaitForExit(1000)) {
            $InstallStatus = '{0:mm\:ss} elapsed - the screen may flicker while the driver installs' -f $InstallTimer.Elapsed
            Write-Progress -Activity 'Installing NVIDIA display driver' -Status $InstallStatus
            if ($InstallTimer.Elapsed.TotalSeconds -ge $NextInstallReport) {
                Write-Host ('  kuruluyor: {0:mm\:ss} (ekran birkac kez kararabilir)' -f $InstallTimer.Elapsed)
                $NextInstallReport += 15
            }
        }
        Write-Progress -Activity 'Installing NVIDIA display driver' -Completed
        [void](Write-DriverData -Kind 'install' -Version $Driver.Version -Elapsed $InstallTimer.Elapsed -ExitCode $Installer.ExitCode)
        if ($Installer.ExitCode -notin @(0, 1)) {
            throw "NVIDIA driver installer failed with exit code $($Installer.ExitCode)."
        }
        if ($Installer.ExitCode -eq 1) {
            Write-Host "The driver installed, but Windows reports that a restart is required. This script will not restart the computer." -ForegroundColor Yellow
        }
        else {
            Write-Host "NVIDIA display driver installer completed successfully. No restart was requested." -ForegroundColor Green
        }

        exit
    }
    catch {
        Write-Host "`nNVIDIA DRIVER ERROR:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        # no Pause: the Launcher shows the failure in its summary, and live/resume runs must not wait for a key
        exit 1
    }
}
