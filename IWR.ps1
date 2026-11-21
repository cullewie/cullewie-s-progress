[CmdletBinding()]
param()

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
$Repository = 'cullewie/cullewie-s-progress'
$PayloadCommit = 'f056579663a7b93788649f877aafa068d125d3ad'
$ExpectedManifestSha256 = '723f877184eadb2de38c3f15f70f7ef20618b3ab78afc783b56bb14f9d3b32ae'
$RawRoot = 'https://raw.githubusercontent.com/' + $Repository + '/' + $PayloadCommit

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Set-PrivateDirectoryAcl {
    param([Parameter(Mandatory=$true)][string]$Path)
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    & $icacls $Path '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not restrict directory permissions: $Path"
    }
}
function Assert-ManifestPath {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '(^|/)\.\.(/|$)' -or
        $RelativePath.Contains(':') -or
        $RelativePath.Contains('\')) {
        throw "Unsafe manifest path: $RelativePath"
    }
}

try {
    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        throw 'Windows PowerShell 5.1 or newer is required.'
    }
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit PowerShell on 64-bit Windows.'
    }
    if (-not (Test-Administrator)) {
        throw 'Open PowerShell with Run as administrator, then run the one-line command again.'
    }
    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10 -or $osVersion.Build -lt 22000) {
        throw 'This release requires Windows 11 (build 22000 or newer).'
    }
    if ($PayloadCommit -notmatch '^[0-9a-f]{40}$' -or $ExpectedManifestSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'The bootstrap release pins have not been configured.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $programDataRoot = Join-Path $env:ProgramData 'Cullewie'
    $releasesRoot = Join-Path $programDataRoot 'Releases'
    $stagingRoot = Join-Path $programDataRoot 'Staging'
    New-Item -ItemType Directory -Force -Path $releasesRoot,$stagingRoot | Out-Null
    Set-PrivateDirectoryAcl -Path $releasesRoot
    Set-PrivateDirectoryAcl -Path $stagingRoot

    $releaseId = '1.0.12-' + $PayloadCommit.Substring(0,12)
    $releasePath = Join-Path $releasesRoot $releaseId
    $manifestUrl = $RawRoot + '/manifest.json'
    $activePath = $releasePath

    if (-not (Test-Path -LiteralPath $releasePath -PathType Container)) {
        $stagePath = Join-Path $stagingRoot ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagePath | Out-Null
        Set-PrivateDirectoryAcl -Path $stagePath

        $manifestPath = Join-Path $stagePath 'manifest.json'
        Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -OutFile $manifestPath -TimeoutSec 60
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($manifestHash -ne $ExpectedManifestSha256) {
            throw 'manifest.json SHA-256 did not match the bootstrap pin.'
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.schemaVersion -ne 1 -or $manifest.release.version -ne '1.0.12') {
            throw 'Unsupported manifest schema or release version.'
        }
        if (@($manifest.files).Count -eq 0) {
            throw 'Manifest has no files.'
        }

        $stagePrefix = [System.IO.Path]::GetFullPath($stagePath).TrimEnd('\') + '\'
        foreach ($entry in $manifest.files) {
            Assert-ManifestPath -RelativePath ([string]$entry.path)
            if ([string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [int64]$entry.size -lt 0) {
                throw "Invalid file metadata in manifest: $($entry.path)"
            }
            $destination = Join-Path $stagePath ($entry.path -replace '/', '\')
            $destinationFull = [System.IO.Path]::GetFullPath($destination)
            if (-not $destinationFull.StartsWith($stagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Manifest path escapes the release directory: $($entry.path)"
            }
            $parent = Split-Path -Parent $destinationFull
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
            $encodedPath = (($entry.path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
            $fileUrl = $RawRoot + '/' + $encodedPath
            Invoke-WebRequest -Uri $fileUrl -UseBasicParsing -OutFile $destinationFull -TimeoutSec 120
            $file = Get-Item -LiteralPath $destinationFull
            if ([int64]$file.Length -ne [int64]$entry.size) {
                throw "File size mismatch: $($entry.path)"
            }
            $fileHash = (Get-FileHash -LiteralPath $destinationFull -Algorithm SHA256).Hash
            if ($fileHash -ine [string]$entry.sha256) {
                throw "SHA-256 mismatch: $($entry.path)"
            }
        }

        Move-Item -LiteralPath $stagePath -Destination $releasePath
        Set-PrivateDirectoryAcl -Path $releasePath
    }
    else {
        Set-PrivateDirectoryAcl -Path $releasePath
        $manifestPath = Join-Path $releasePath 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw 'Existing release has no manifest; refusing to overwrite it.'
        }
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($manifestHash -ne $ExpectedManifestSha256) {
            throw 'Existing release manifest failed SHA-256 verification.'
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.files) {
            Assert-ManifestPath -RelativePath ([string]$entry.path)
            $filePath = Join-Path $releasePath ($entry.path -replace '/', '\')
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Existing release file is missing: $($entry.path)"
            }
            $file = Get-Item -LiteralPath $filePath
            $fileHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
            if ([int64]$file.Length -ne [int64]$entry.size -or $fileHash -ine [string]$entry.sha256) {
                throw "Existing release file failed verification: $($entry.path)"
            }
        }
    }

    $launcher = Join-Path $activePath 'Launcher.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw 'Verified release does not contain Launcher.ps1.'
    }
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw 'Windows PowerShell executable was not found.'
    }
    Write-Host "Verified release: $releaseId" -ForegroundColor Green
    Write-Host 'Starting the interactive launcher. No optimization is applied automatically.' -ForegroundColor Cyan
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $launcher
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Launcher exit code: $LASTEXITCODE" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Bootstrap stopped: $($_.Exception.Message)" -ForegroundColor Red
    if ($stagePath -and (Test-Path -LiteralPath $stagePath -PathType Container)) {
        Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}
}
