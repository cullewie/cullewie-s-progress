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

# ---------------- Tweaks.ps1 (static only: Tweaks is never run here) ----------------
$tweaks = Join-Path $repo 'Scripts\Windows\Tweaks.ps1'
$t = Get-Ast $tweaks
$offOnly = @('^Set-Reg .*"GlobalUserDisabled"', '^Set-Reg .*"LetAppsRunInBackground"')
$notXbox = @("^Remove-MsiProduct '\*Microsoft GameInput\*'", 'XboxGamingOverlay \| Remove-AppxPackage', "^Import-Reg 'gamebaroff'", '^Run-Trusted .*PresenceWriter')
$unguarded = @($offOnly | Where-Object { -not (Test-Guarded $t.Ast $_ "`$Apps -eq 'off'") }) + @($notXbox | Where-Object { -not (Test-Guarded $t.Ast $_ "`$Apps -ne 'xbox'") })
Assert ($unguarded.Count -eq 0) 'Tweaks-Guards' "unguarded: $($unguarded -join ' | ')"

$removeFn = Get-FunctionText $t.Ast 'Remove-RegKeyBlock'
$cpText = Get-HereString $t.Ast '$controlPanel'
if ($removeFn -and $cpText) {
    Invoke-Expression $removeFn
    foreach ($k in 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate', 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy', 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications') { $cpText = Remove-RegKeyBlock $cpText $k }
    Assert ($cpText -notmatch 'AutoDownload|LetAppsRunInBackground|GlobalUserDisabled' -and $cpText -match 'LongPathsEnabled' -and $cpText -match 'IsPrelaunchEnabled') 'Tweaks-RemoveRegKeyBlock'
} else { Assert $false 'Tweaks-RemoveRegKeyBlock' 'function or $controlPanel missing' }

$setRegFn = Get-FunctionText $t.Ast 'Set-Reg'
$policyFn = Get-FunctionText $t.Ast 'Set-AppsUpdatePolicy'
if ($setRegFn -and $policyFn) {
    Invoke-Expression $setRegFn; Invoke-Expression $policyFn
    $root = 'HKCU:\Software\ClaudeAppsTest'
    try {
        Set-AppsUpdatePolicy -PolicyKey "$root\WU" -UxKey "$root\UX" -DisplayVersion '25H2'
        $wu = Get-Item "$root\WU"; $ux = Get-Item "$root\UX"
        $ok = $wu.GetValue('TargetReleaseVersion') -eq 1 -and $wu.GetValueKind('TargetReleaseVersion') -eq 'DWord' -and
              $wu.GetValue('ProductVersion') -eq 'Windows 11' -and $wu.GetValueKind('ProductVersion') -eq 'String' -and
              $wu.GetValue('TargetReleaseVersionInfo') -eq '25H2' -and $wu.GetValueKind('TargetReleaseVersionInfo') -eq 'String' -and
              $wu.GetValue('ExcludeWUDriversInQualityUpdate') -eq 1 -and $wu.GetValue('AllowOptionalContent') -eq 0 -and
              $wu.GetValue('SetAllowOptionalContent') -eq 0 -and $wu.GetValueKind('SetAllowOptionalContent') -eq 'DWord' -and
              $ux.GetValue('IsContinuousInnovationOptedIn') -eq 0 -and $ux.GetValueKind('IsContinuousInnovationOptedIn') -eq 'DWord'
        Assert $ok 'Tweaks-UpdatePolicy'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
} else { Assert $false 'Tweaks-UpdatePolicy' 'Set-Reg or Set-AppsUpdatePolicy missing' }

$loop = $t.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Condition.Extent.Text -match 'ms_lldp' }, $true) | Select-Object -First 1
$listText = $loop.Condition.Extent.Text
$listFor = { param($level) $Apps = $level; @(Invoke-Expression $listText) }
Assert ($listText -match '\$Apps' -and (& $listFor 'xbox') -notcontains 'ms_tcpip6' -and (& $listFor 'store') -contains 'ms_tcpip6' -and (& $listFor 'off') -contains 'ms_tcpip6' -and (& $listFor 'xbox') -contains 'ms_server') 'Tweaks-BindingList'
$relaunchT = Select-String -Path $tweaks -Pattern 'Start-Process PowerShell\.exe' | Select-Object -First 1
Assert (-not $relaunchT -or $relaunchT.Line -match '\$Apps') 'Tweaks-RelaunchForwardsApps'
$tParams = @($t.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert ($t.Errors.Count -eq 0 -and $tParams -contains 'Apps' -and $tParams -contains 'DryRun') 'Tweaks-Parses' "errors=$($t.Errors.Count) params=$($tParams -join ',')"

# ---------------- Launcher.ps1 and IWR.ps1 (static only) ----------------
$launcher = Join-Path $repo 'Launcher.ps1'
$l = Get-Ast $launcher
$full = Get-FunctionText $l.Ast 'Start-FullSetup'; $resume = Get-FunctionText $l.Ast 'Resume-FullSetup'; $live = Get-FunctionText $l.Ast 'Start-LiveSetup'
if ($full -and $resume -and $live) {
    $iRemove = $full.IndexOf('Remove-Item -LiteralPath $script:AppsFlag'); $iAsk = $full.IndexOf('Read-AppsChoice'); $iTool = $full.IndexOf('Invoke-RequiredTool')
    $count = { param($text) ([regex]::Matches($text, 'Get-AppsArguments')).Count }
    Assert ($iRemove -ge 0 -and $iRemove -lt $iAsk -and $iAsk -lt $iTool -and $resume -notmatch 'Read-AppsChoice' -and (& $count $resume) -ge 2 -and (& $count $live) -ge 2) 'Launcher-FlagLifecycle' "remove=$iRemove ask=$iAsk tool=$iTool resumeArgs=$(& $count $resume) liveArgs=$(& $count $live)"
    Assert ($live -notmatch 'Read-Host|Read-AppsChoice' -and $live -match 'ConvertTo-AppsLevel \$Apps' -and $live -match '\$script:AppsFlag') 'Launcher-LiveNoPrompt'
} else { Assert $false 'Launcher-FlagLifecycle' 'functions missing'; Assert $false 'Launcher-LiveNoPrompt' 'functions missing' }
$convert = Get-FunctionText $l.Ast 'ConvertTo-AppsLevel'
if ($convert) {
    $results = & { Set-StrictMode -Version Latest; Invoke-Expression $convert; @((ConvertTo-AppsLevel 'store'), (ConvertTo-AppsLevel 'XBOX '), (ConvertTo-AppsLevel ''), (ConvertTo-AppsLevel $null), (ConvertTo-AppsLevel 'abc')) }
    Assert (($results -join ',') -eq 'store,xbox,off,off,off') 'Launcher-AppsValue' "got $($results -join ',')"
} else { Assert $false 'Launcher-AppsValue' 'ConvertTo-AppsLevel missing' }
$getArgs = Get-FunctionText $l.Ast 'Get-AppsArguments'
if ($convert -and $getArgs) {
    $flag = [IO.Path]::GetTempFileName()
    $r = & {
        Set-StrictMode -Version Latest
        $script:AppsFlag = $flag
        Invoke-Expression $convert; Invoke-Expression $getArgs
        Set-Content $flag 'xbox'; $a = (@('-Live') + @(Get-AppsArguments)) -join ' '
        Set-Content $flag 'junk'; $b = @(Get-AppsArguments).Count
        Remove-Item $flag; $c = @(Get-AppsArguments).Count
        "$a|$b|$c"
    }
    Remove-Item $flag -ErrorAction SilentlyContinue
    Assert ($r -eq '-Live -Apps xbox|0|0') 'Launcher-AppsArguments' "got $r"
} else { Assert $false 'Launcher-AppsArguments' 'functions missing' }
$question = 'Microsoft Store / Xbox kullaniyor musunuz? 1 = Hayir, 2 = Sadece Microsoft Store, 3 = Xbox ve Game Pass (Store dahil)'
Assert ([IO.File]::ReadAllText($launcher).Contains($question)) 'Launcher-Question'
$lParams = @($l.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert ($l.Errors.Count -eq 0 -and $lParams -contains 'Apps') 'Launcher-Parses' "errors=$($l.Errors.Count)"
$iwr = Join-Path $repo 'IWR.ps1'
$iwrText = [IO.File]::ReadAllText($iwr)
$bareLf = [regex]::Matches($iwrText, '(?<!\r)\n').Count
Assert ($iwrText -match 'CULLEWIE_APPS' -and $iwrText -match "'-Apps'" -and $bareLf -eq 0 -and (Get-Ast $iwr).Errors.Count -eq 0) 'IWR-ForwardsApps' "bareLF=$bareLf"

exit $script:failures
