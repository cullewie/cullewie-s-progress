1 {
    Clear-Host

    $ErrorActionPreference = "Stop"
    # Keep PowerShell's download progress visible in the console.
    $ProgressPreference = "Continue"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Headers = @{
        "User-Agent" = "Mozilla/5.0"
    }

    try {
        Write-Host "DETECTING NVIDIA GPU..." -ForegroundColor Yellow

        $GPUs = @(
            Get-CimInstance Win32_VideoController |
            Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE&*' }
        )

        if ($GPUs.Count -ne 1) {
            throw "Expected exactly one NVIDIA GPU. Found: $($GPUs.Count)"
        }

        $GPU = $GPUs[0]

        Write-Host "GPU: $($GPU.Name)" -ForegroundColor Green

        # NVIDIA lookup API
        $API = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID="

        $Series = (Invoke-RestMethod `
            -Uri "${API}2" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        $Products = (Invoke-RestMethod `
            -Uri "${API}3" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        $OSList = (Invoke-RestMethod `
            -Uri "${API}4" -Headers $Headers -UseBasicParsing).LookupValueSearch.LookupValues.LookupValue

        # Match GPU
        $Product = $Products |
            Where-Object { $_.Name -eq $GPU.Name } |
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

        # Download
        $TargetPath = Join-Path "$env:SystemRoot\Temp" "nvidia-driver-$($Driver.Version).exe"

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

        Invoke-WebRequest `
            -Uri $Driver.DownloadURL `
            -Headers $Headers `
            -UseBasicParsing `
            -OutFile $TargetPath `
            -TimeoutSec 3600

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

        Write-Host "OPENING NVIDIA INSTALLER..." -ForegroundColor Green

        Start-Process -FilePath $TargetPath

        exit
    }
    catch {
        Write-Host "`nNVIDIA DRIVER ERROR:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        Pause
        exit
    }
}
