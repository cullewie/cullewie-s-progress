# Windows Update before the setup: a PC fresh from a format has updates waiting, and a restart they wait for would be
# applied at the safe-mode boot, fail there and get rolled back. This step downloads and installs them first, through
# the Windows Update client itself (the same service as Settings > Windows Update).
#  - only software updates: no drivers (the GPU driver comes from DDU and the driver step), no new Windows version
#    (the "Upgrades" category) and no optional updates (previews)
#  - nothing asks a question: updates that need user input are left out
#  - it does not restart: the Launcher restarts when Windows waits for one, and the setup continues after sign-in
# Exit 0 = done (installed, nothing to install, nothing downloaded, or skipped); 1 = search or install error.
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# a PC an earlier All-in set up has Windows Update disabled: no update round then
$wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
if (-not $wu -or $wu.StartType -eq 'Disabled') {
    Write-Host 'Windows Update: the service is disabled (an earlier setup turned it off); skipped.' -ForegroundColor Yellow
    exit 0
}

try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'cullewie-s-progress'
    Write-Host 'Windows Update: searching (this can take a few minutes)...'
    $found = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $updates = New-Object -ComObject Microsoft.Update.UpdateColl
    # Insider / preview builds list the cumulative update of the build they already run ("(26300.10075)" on 26300.10075)
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $thisBuild = "($($cv.CurrentBuildNumber).$($cv.UBR))"
    foreach ($u in $found.Updates) {
        if ($u.Title -like "*$thisBuild*") { Write-Host "  skip  $($u.Title) (this build is already installed)" -ForegroundColor DarkGray; continue }
        $categories = @($u.Categories | ForEach-Object { $_.Name })
        if ($categories -contains 'Upgrades') { Write-Host "  skip  $($u.Title) (new Windows version)" -ForegroundColor DarkGray; continue }
        if ($u.BrowseOnly) { Write-Host "  skip  $($u.Title) (optional)" -ForegroundColor DarkGray; continue }
        if ($u.InstallationBehavior.CanRequestUserInput) { Write-Host "  skip  $($u.Title) (asks for input)" -ForegroundColor DarkGray; continue }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$updates.Add($u)
        Write-Host "  get   $($u.Title)"
    }
    if ($updates.Count -eq 0) {
        Write-Host 'Windows Update: nothing to install.' -ForegroundColor Green
        exit 0
    }

    Write-Host "Windows Update: downloading $($updates.Count) update(s)..."
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $download = $downloader.Download()

    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    $noPackage = 0
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $u = $updates.Item($i)
        if ($u.IsDownloaded) { [void]$ready.Add($u); continue }
        $hr = '0x{0:X8}' -f $download.GetUpdateResult($i).HResult
        # 0xC1900401 = no package to download: Insider / preview builds list updates that only Settings can get
        if ($hr -eq '0xC1900401') { $noPackage++; Write-Host "  skip  $($u.Title) (no package for this build, $hr)" -ForegroundColor DarkGray }
        else { Write-Host "  not downloaded  $($u.Title) ($hr)" -ForegroundColor Yellow }
    }
    # nothing downloaded = nothing to install: the setup continues (Settings > Windows Update can get it later)
    if ($ready.Count -eq 0) {
        if ($noPackage -eq $updates.Count) { Write-Host 'Windows Update: nothing this tool can install; skipped.' -ForegroundColor Yellow; exit 0 }
        Write-Host 'Windows Update: nothing could be downloaded; skipped.' -ForegroundColor Yellow; exit 0
    }

    Write-Host "Windows Update: installing $($ready.Count) update(s)..."
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $ready
    $result = $installer.Install()
    # OperationResultCode: 2 = succeeded, 3 = succeeded with errors, 4 = failed, 5 = aborted
    for ($i = 0; $i -lt $ready.Count; $i++) {
        $one = $result.GetUpdateResult($i)
        $code = $one.ResultCode
        $text = switch ($code) { 2 { 'ok   ' } 3 { 'ok*  ' } default { 'FAIL ' } }
        $hr = if ($code -in 2, 3) { '' } else { ' ({0})' -f ('0x{0:X8}' -f $one.HResult) }
        Write-Host "  $text $($ready.Item($i).Title)$hr" -ForegroundColor $(if ($code -in 2, 3) { 'Green' } else { 'Red' })
    }
    if ($result.RebootRequired) { Write-Host 'Windows Update: a restart finishes the installation.' -ForegroundColor Cyan }
    if ($result.ResultCode -in 2, 3) { exit 0 }
    Write-Host "Windows Update: installation result $($result.ResultCode)." -ForegroundColor Red
    exit 1
}
catch {
    Write-Host "Windows Update: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
