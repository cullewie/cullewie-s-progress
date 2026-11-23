# Static tests for the Store/Xbox option (-Apps off|store|xbox). Read-only: the only writes are temp files and
# HKCU:\Software\ClaudeAppsTest. Run from an elevated Windows PowerShell 5.1:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Apps.Tests.ps1
# Exit code = number of failed tests.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$script:failures = 0
function Assert([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { Write-Host "PASS $Name" -ForegroundColor Green }
    else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:failures++ }
}
function Get-Plan([string]$Path) {
    $plan = @{}
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($Path), '(?m)^\[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\([^\]]+)\]\r?\n"Start"=dword:0*(\d)')) {
        $plan[$m.Groups[1].Value] = [int]$m.Groups[2].Value
    }
    $plan
}
function Get-Ast([string]$Path) {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
    [pscustomobject]@{ Ast = $ast; Errors = @($errors) }
}
function Get-HereString($Ast, [string]$Variable) {
    ($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $Variable }, $true) | Select-Object -First 1).Right.Expression.Value
}
function Get-FunctionText($Ast, [string]$Name) {
    ($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true) | Select-Object -First 1).Extent.Text
}
# true when the first statement whose text matches $Pattern sits inside an if whose condition text is $Condition
function Test-Guarded($Ast, [string]$Pattern, [string]$Condition) {
    $node = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.PipelineAst] -and $n.Extent.Text -match $Pattern }, $true) | Select-Object -First 1
    if (-not $node) { return $false }
    for ($p = $node.Parent; $p; $p = $p.Parent) {
        if ($p -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in $p.Clauses) { if ($clause.Item1.Extent.Text -eq $Condition -and $clause.Item2.Extent.StartOffset -le $node.Extent.StartOffset -and $clause.Item2.Extent.EndOffset -ge $node.Extent.EndOffset) { return $true } }
        }
    }
    $false
}
$storeStart = @{ wuauserv = 3; BITS = 3; UsoSvc = 2; WaaSMedicSvc = 3; PushToInstall = 3 }
$xboxStart = $storeStart.Clone()
foreach ($k in @{ XblAuthManager = 3; XblGameSave = 3; XboxGipSvc = 3; XboxNetApiSvc = 3; iphlpsvc = 2; GameInputSvc = 3; WpnService = 2; WpnUserService = 2 }.GetEnumerator()) { $xboxStart[$k.Key] = $k.Value }

# ---------------- Services.ps1 ----------------
$services = Join-Path $repo 'Scripts\Windows\Services.ps1'
# SAFETY: Services.ps1 has no [CmdletBinding()], so an unknown -PlanOnly would be ignored and the REAL setup would run
# (safe mode, restart). Only invoke it when its param block really declares PlanOnly and PlanPath.
$servicesParams = @((Get-Ast $services).Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$canPlan = ($servicesParams -contains 'PlanOnly') -and ($servicesParams -contains 'PlanPath') -and ($servicesParams -contains 'Apps')
function Invoke-ServicesPlan([string[]]$Extra) {
    if (-not $canPlan) { return [pscustomobject]@{ Exit = -1; Plan = @{}; Path = $null } }
    $tmp = [IO.Path]::GetTempFileName()
    & $ps -NoProfile -ExecutionPolicy Bypass -File $services -PlanOnly -PlanPath $tmp @Extra | Out-Null
    [pscustomobject]@{ Exit = $LASTEXITCODE; Plan = (Get-Plan $tmp); Path = $tmp }
}
$off = Invoke-ServicesPlan @()
Assert ($off.Exit -eq 0 -and $off.Plan.Count -eq 248 -and $off.Plan['BITS'] -eq 4 -and $off.Plan['wuauserv'] -eq 4 -and $off.Plan['XblAuthManager'] -eq 4) 'Off-PlanUnchanged' "exit=$($off.Exit) count=$($off.Plan.Count)"
Assert ($off.Plan['cbdhsvc'] -eq 3) 'Off-ClipboardStaysManual' "cbdhsvc=$($off.Plan['cbdhsvc'])"
$store = Invoke-ServicesPlan @('-Apps', 'store')
$bad = @($storeStart.Keys | Where-Object { $store.Plan[$_] -ne $storeStart[$_] })
Assert ($store.Exit -eq 0 -and $store.Plan.Count -eq 248 -and -not $bad -and $store.Plan['XblAuthManager'] -eq 4) 'Store-PlanSetsDefaults' "exit=$($store.Exit) wrong=$($bad -join ',')"
$xbox = Invoke-ServicesPlan @('-Apps', 'xbox')
$bad = @($xboxStart.Keys | Where-Object { $xbox.Plan[$_] -ne $xboxStart[$_] })
Assert ($xbox.Exit -eq 0 -and $xbox.Plan.Count -eq 248 -and -not $bad -and $xbox.Plan['DiagTrack'] -eq 4) 'Xbox-PlanSetsDefaults' "exit=$($xbox.Exit) wrong=$($bad -join ',')"
$off, $store, $xbox | Where-Object Path | ForEach-Object { Remove-Item $_.Path -Force -ErrorAction SilentlyContinue }
$relaunch = (Select-String -Path $services -Pattern 'Start-Process PowerShell\.exe' | Select-Object -First 1).Line
Assert ($relaunch -match '\$Apps') 'Services-RelaunchForwardsApps'
$s = Get-Ast $services
$inner = (Get-HereString $s.Ast '$ServicesOff') -replace "``'@", "'@"
$innerErrors = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($inner, [ref]$null, [ref]$innerErrors)
Assert ($s.Errors.Count -eq 0 -and @($innerErrors).Count -eq 0) 'Services-Parses' "outer=$($s.Errors.Count) inner=$(@($innerErrors).Count)"

exit $script:failures
