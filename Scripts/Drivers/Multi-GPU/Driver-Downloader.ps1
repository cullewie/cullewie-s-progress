# SCRIPT RUN AS ADMIN
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
Exit}
$Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.PrivateData.ProgressBackgroundColor = "Black"
$Host.PrivateData.ProgressForegroundColor = "White"
Clear-Host

function Assert-Publisher([string]$Path, [string]$Publisher) {
$signature = Get-AuthenticodeSignature -LiteralPath $Path
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $Publisher) {
throw "Downloaded file is not signed by $Publisher; it was not started: $Path"
}
}

# SCRIPT SILENT
# Keep download progress visible in the console.
$ProgressPreference = 'Continue'

Write-Host "INSTALL UPDATED GRAPHICS DRIVER" -ForegroundColor Yellow
Write-Host " 1.  NVIDIA" -ForegroundColor Green
Write-Host " 2.  AMD" -ForegroundColor Red
Write-Host " 3.  INTEL`n" -ForegroundColor Blue
while ($true) {
$choice = Read-Host " "
if ($choice -match '^[1-3]$') {
switch ($choice) {
1 {

Clear-Host

Write-Host "NVIDIA APP TURN OFF:"
Write-Host "- Statistics"
Write-Host "- Game Filters"
Write-Host "- Automatically optimize newly added games and apps`n"

# find latest nvidia driver
$uri = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=120&pfid=929&osID=57&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1'
$response = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing
$payload = $response.Content | ConvertFrom-Json
$version =  $payload.IDS[0].downloadInfo.Version
$windowsVersion = if ([Environment]::OSVersion.Version -ge (new-object 'Version' 9, 1)) {"win10-win11"} else {"win8-win7"}
$windowsArchitecture = if ([Environment]::Is64BitOperatingSystem) {"64bit"} else {"32bit"}
# Laptops (a battery is present) need NVIDIA's notebook package.
$formFactor = if (Get-CimInstance Win32_Battery) {"notebook"} else {"desktop"}
$url = "https://international.download.nvidia.com/Windows/$version/$version-$formFactor-$windowsVersion-$windowsArchitecture-international-dch-whql.exe"
Write-Output "Downloading: Nvidia Driver $version ..."

# download nvidia driver
IWR $url -OutFile "$env:SystemRoot\Temp\nvidiadriver.exe"
Assert-Publisher "$env:SystemRoot\Temp\nvidiadriver.exe" 'NVIDIA Corporation'
Clear-Host

# open nvidia driver installer
Start-Process "$env:SystemRoot\Temp\nvidiadriver.exe"

exit

}
2 {

Clear-Host

# download amd driver auto detect
$DownloadAmd = Invoke-WebRequest "https://www.amd.com/en/support/download/drivers.html" -UseBasicParsing |
Select-Object -ExpandProperty Links |
Where-Object { $_.href -match "drivers\.amd.com/drivers/installer/.*/whql/amd-software-adrenalin-edition-.*-minimalsetup-.*_web\.exe" } | Select-Object href
$spoofwebbrowser = @{
"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
"Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
"Referer"    = "https://www.amd.com/"
}
$amdLinks = @($DownloadAmd.href | Select-Object -Unique)
if ($amdLinks.Count -ne 1) { throw "Expected one AMD installer link on the AMD page. Found: $($amdLinks.Count)" }
Remove-Item "$env:SystemRoot\Temp\amddriver.exe" -Force -ErrorAction SilentlyContinue
IWR $amdLinks[0] -UseBasicParsing -Headers $spoofwebbrowser -OutFile "$env:SystemRoot\Temp\amddriver.exe"
Assert-Publisher "$env:SystemRoot\Temp\amddriver.exe" 'Advanced Micro Devices'

# open amd web driver installer
Start-Process "$env:SystemRoot\Temp\amddriver.exe"

exit

}
3 {

Clear-Host

# open intel driver web page
Start-Process "https://www.intel.com/content/www/us/en/search.html#sortCriteria=%40lastmodifieddt%20descending&f-operatingsystem_en=Windows%2011%20Family*&f-downloadtype=Drivers&cf-tabfilter=Downloads&cf-downloadsppth=Graphics"

exit

}
} } else { Write-Host "Invalid input. Please select a valid option (1-3)." } }
