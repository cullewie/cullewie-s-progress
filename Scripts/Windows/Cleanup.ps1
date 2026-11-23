# Disk cleanup at the very end, started from the Done window (Apply, Skip or closing it). Only the system drive:
# Windows' Disk Cleanup (cleanmgr /sagerun) scans every drive, USB sticks included, and it hung there.
# -ResultPath: a file the window reads ("freed=<bytes>"). -Restart: restart Windows when done, so closing the window
# does not stop it.
param([string]$ResultPath, [switch]$Restart)

# what is deleted (folders whose contents go are written with \*)
function Get-CleanupTargets {
    @(
        "$env:TEMP\*"
        "$env:SystemRoot\Temp\*"
        "$env:SystemRoot\SoftwareDistribution\Download\*"
        "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*"
        "$env:SystemRoot\Minidump\*"
        "$env:SystemRoot\MEMORY.DMP"
        "$env:LOCALAPPDATA\CrashDumps\*"
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*"
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*"
        "$env:SystemDrive\NVIDIA"
        "$env:SystemDrive\AMD"
    )
}
# freed space for the window: "2,3 GB" or "512 MB" (Turkish decimal comma)
function Format-Freed([int64]$Bytes) {
    if ($Bytes -lt 0) { $Bytes = 0 }
    if ($Bytes -ge 1GB) { return ([double]$Bytes / 1GB).ToString('0.0', [Globalization.CultureInfo]'tr-TR') + ' GB' }
    return ([int][math]::Round([double]$Bytes / 1MB)).ToString() + ' MB'
}

$drive = $env:SystemDrive.TrimEnd(':')
$before = (Get-PSDrive $drive).Free
# files in use (a running program's temp file, a thumbnail Explorer holds) are skipped
foreach ($t in Get-CleanupTargets) { Remove-Item -Path $t -Recurse -Force -ErrorAction SilentlyContinue }
Clear-RecycleBin -DriveLetter $env:SystemDrive[0] -Force -ErrorAction SilentlyContinue
# old copies of Windows components left by updates; at most 20 minutes
$dism = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup /NoRestart' -WindowStyle Hidden -PassThru
if (-not $dism.WaitForExit(20 * 60 * 1000)) { & "$env:SystemRoot\System32\taskkill.exe" /PID $dism.Id /T /F 2>$null | Out-Null }
$freed = (Get-PSDrive $drive).Free - $before
Write-Host ('Freed: ' + (Format-Freed $freed))
if ($ResultPath) { Set-Content -Path $ResultPath -Value ('freed=' + [int64]$freed) -Encoding ASCII }
if ($Restart) { cmd /c "shutdown /r /t 10 /c `"Disk temizlendi, bilgisayar yeniden basliyor.`" >nul 2>&1" }
exit 0
