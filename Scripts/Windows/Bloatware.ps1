# Removes preinstalled apps, optional Windows capabilities and legacy features that a gaming PC does not need.
# Kept: Windows shell, Start and search, File Explorer, Notepad, Paint, Photos, Calculator, Terminal, Snipping Tool,
# media codecs, Windows Security, the GPU control panels, Wi-Fi/Ethernet, and every language component of the
# languages in use (Turkish always). -DryRun only writes what would be removed to bloatware-dryrun.txt.
param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$log = Join-Path $env:ProgramData 'Cullewie\Work\bloatware-dryrun.txt'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
if ($DryRun) { Set-Content -Path $log -Value "Dry run $(Get-Date -Format s)" -Encoding UTF8 }
function Write-Plan([string]$Kind, [string]$Name) { if ($DryRun) { Add-Content -Path $log -Value "$Kind`t$Name" -Encoding UTF8 } }

# languages in use: display language, regional format, keyboard languages, system locale; Turkish always
$languages = @('tr-TR', (Get-UICulture).Name, (Get-Culture).Name, (Get-WinSystemLocale).Name) + @((Get-WinUserLanguageList).LanguageTag)
$languages = @($languages | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
# a bare tag like "tr" also covers "tr-TR"
function Test-KeptLanguage([string]$Text) {
    foreach ($l in $languages) { if ($Text -match "(?i)(~~~|LanguageExperiencePack|\b)$([regex]::Escape($l))(-[a-z]{2})?(~|$)") { return $true } }
    return $false
}

Write-Host 'Removing apps...'
$keepApps = @(
    '*CBS*', 'MicrosoftWindows.Client.*', 'Microsoft.Windows.Search*',                       # Start, search, taskbar parts
    'Microsoft.Windows.ShellExperienceHost*', 'Microsoft.Windows.StartMenuExperienceHost*', 'windows.immersivecontrolpanel*',
    'Microsoft.AV1VideoExtension*', 'Microsoft.AVCEncoderVideoExtension*', 'Microsoft.HEIFImageExtension*', 'Microsoft.HEVCVideoExtension*',
    'Microsoft.MPEG2VideoExtension*', 'Microsoft.RawImageExtension*', 'Microsoft.VP9VideoExtensions*', 'Microsoft.WebMediaExtensions*', 'Microsoft.WebpImageExtension*',
    'Microsoft.Paint*', 'Microsoft.Windows.Photos*', 'Microsoft.WindowsNotepad*', 'Microsoft.SecHealthUI*',
    'Microsoft.WindowsCalculator*', 'Microsoft.WindowsTerminal*', 'Microsoft.ScreenSketch*',
    'NVIDIACorp.NVIDIAControlPanel*', 'AdvancedMicroDevicesInc*',
    'Microsoft.LanguageExperiencePack*',
    'Microsoft.AsyncTextService*', '*InpApp*', '*Speion*',                                     # text input, emoji panel, speech
    'Microsoft.CredDialogHost*', 'Microsoft.AAD.BrokerPlugin*', 'Microsoft.AccountsControl*', # sign-in and password dialogs
    'Microsoft.LockApp*', 'Microsoft.Windows.CloudExperienceHost*', 'Microsoft.BioEnrollment*', 'Microsoft.Win32WebViewHost*',
    'Microsoft.Windows.CapturePicker*', 'Microsoft.DirectXRuntime*'
)
foreach ($app in Get-AppxPackage -AllUsers) {
    $name = $app.Name
    # shared runtimes the kept apps and games depend on
    if ($app.IsFramework) { continue }
    if ($keepApps | Where-Object { $name -like $_ }) { continue }
    Write-Plan 'app' $name
    if (-not $DryRun) { $app | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
}

Write-Host 'Removing optional capabilities...'
$keepCapabilities = @(
    '*Microsoft.Windows.Ethernet*', '*Microsoft.Windows.Wifi*', '*Microsoft.Windows.MSPaint*', '*Microsoft.Windows.Notepad*',
    '*NetFX3*', '*VBSCRIPT*', '*WMIC*', '*Windows.Client.ShellComponents*', '*DirectX.Configuration.Database*'
)
foreach ($cap in Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' }) {
    $name = $cap.Name
    if ($keepCapabilities | Where-Object { $name -like $_ }) { continue }
    if ($name -like 'Language.*' -and (Test-KeptLanguage $name)) { continue }
    Write-Plan 'capability' $name
    if (-not $DryRun) { try { Remove-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null } catch { } }
}

Write-Host 'Turning off legacy features...'
$keepFeatures = @(
    '*DirectPlay*', '*LegacyComponents*', '*NetFx3*', '*NetFx4*', '*SearchEngine-Client-Package*', '*Windows-Defender*',
    '*Server-Shell*', '*Server-Drivers-General*', '*ServerCore-Drivers-General*', '*Server-Gui-Mgmt*', '*WirelessNetworking*'
)
foreach ($feature in Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' }) {
    $name = $feature.FeatureName
    if ($keepFeatures | Where-Object { $name -like $_ }) { continue }
    Write-Plan 'feature' $name
    if (-not $DryRun) { try { Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null } catch { } }
}

Write-Host 'Removing legacy apps...'
$uninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
function Remove-MsiProduct([string]$Like) {
    foreach ($p in Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Like }) {
        Write-Plan 'program' $p.DisplayName
        if (-not $DryRun) { Start-Process 'msiexec.exe' -ArgumentList "/x $($p.PSChildName) /qn /norestart" -Wait -NoNewWindow }
    }
}
Remove-MsiProduct '*Microsoft GameInput*'
Remove-MsiProduct '*Update for x64-based Windows Systems*'
Remove-MsiProduct '*Microsoft Update Health Tools*'
Write-Plan 'program' 'OneDrive'
Write-Plan 'program' 'Remote Desktop Connection'
Write-Plan 'program' 'braille driver (brlapi)'
if (-not $DryRun) {
    # braille driver
    cmd /c "sc stop `"brlapi`" >nul 2>&1"
    cmd /c "sc delete `"brlapi`" >nul 2>&1"
    cmd /c "takeown /f `"$env:SystemRoot\brltty`" /r /d y >nul 2>&1"
    cmd /c "icacls `"$env:SystemRoot\brltty`" /grant *S-1-5-32-544:F /t >nul 2>&1"
    Remove-Item "$env:SystemRoot\brltty" -Recurse -Force -ErrorAction SilentlyContinue
    cmd /c "reg delete `"HKLM\SYSTEM\ControlSet001\Services\uhssvc`" /f >nul 2>&1"
    Unregister-ScheduledTask -TaskName PLUGScheduler -Confirm:$false -ErrorAction SilentlyContinue

    # OneDrive
    Stop-Process -Force -Name OneDrive -ErrorAction SilentlyContinue
    cmd /c "$env:SystemRoot\System32\OneDriveSetup.exe -uninstall >nul 2>&1"
    Get-ChildItem -Path "$env:ProgramFiles*\Microsoft OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive" -Filter 'OneDriveSetup.exe' -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { Start-Process -Wait $_.FullName -ArgumentList '/uninstall /allusers' -WindowStyle Hidden -ErrorAction SilentlyContinue }
    cmd /c "$env:SystemRoot\SysWOW64\OneDriveSetup.exe -uninstall >nul 2>&1"
    Get-ScheduledTask | Where-Object { $_.TaskName -match 'OneDrive' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    # Remote Desktop Connection: the uninstaller opens a window, close it as soon as it appears
    Start-Process 'mstsc' -ArgumentList '/Uninstall' -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 100; $i++) {
        $p = Get-Process -Name mstsc -ErrorAction SilentlyContinue
        if (-not $p) { break }
        if ($p.MainWindowHandle -ne 0) { Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue; break }
        Start-Sleep -Milliseconds 100
    }
    Stop-Process -Name mstsc -Force -ErrorAction SilentlyContinue
}

if ($DryRun) { Write-Host "Dry run: nothing was removed. List: $log" -ForegroundColor Yellow } else { Write-Host 'Done.' -ForegroundColor Green }
exit 0
