# TESTLOG (temporary): a log of every setup run for the owner's test runs. Removed after the tests (git grep TESTLOG).
# Each run gets a folder under C:\ProgramData\Cullewie\Logs: steps.log (one line per step), NN-<step>.log (the full
# output of each step) and boots.log (errors and warnings of each boot). current.txt points at the run in progress,
# so the steps after a restart land in the same folder. Nothing here may ever stop the setup: every function swallows
# its own errors.
$script:TestLogRoot = Join-Path $env:ProgramData 'Cullewie\Logs'

function Get-TestRun([string]$Root = $script:TestLogRoot) {
    try {
        $pointer = Join-Path $Root 'current.txt'
        if (-not (Test-Path -LiteralPath $pointer)) { return $null }
        $dir = (Get-Content -LiteralPath $pointer -Raw -ErrorAction Stop).Trim()
        if ($dir -and (Test-Path -LiteralPath $dir)) { return $dir }
    }
    catch { }
    $null
}

function Write-TestStep([string]$Step, [string]$Result, [int]$ExitCode = 0, [timespan]$Duration = [timespan]::Zero, [string]$Root = $script:TestLogRoot) {
    try {
        $run = Get-TestRun -Root $Root
        if (-not $run) { return }
        $line = '{0:yyyy-MM-ddTHH:mm:ss}{1}{2}{1}{3}{1}exit {4}{1}{5:mm\:ss}' -f (Get-Date), "`t", $Step, $Result, $ExitCode, $Duration
        Add-Content -LiteralPath (Join-Path $run 'steps.log') -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Get-TestStepLog([string]$Step, [string]$Root = $script:TestLogRoot) {
    try {
        $run = Get-TestRun -Root $Root
        if (-not $run) { return $null }
        $count = @(Get-ChildItem -LiteralPath $run -Filter '??-*.log' -ErrorAction Stop).Count
        Join-Path $run ('{0:00}-{1}.log' -f ($count + 1), ($Step -creplace '[^A-Za-z0-9-]', '-'))
    }
    catch { $null }
}

function Save-BootEvents([string]$Root = $script:TestLogRoot) {
    try {
        $run = Get-TestRun -Root $Root
        if (-not $run) { return }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $boot = $os.LastBootUpTime
        $marker = Join-Path $run 'lastboot.txt'
        $since = (Get-Item -LiteralPath $run).CreationTime.AddHours(-1)
        if (Test-Path -LiteralPath $marker) {
            $previous = [datetime]::Parse((Get-Content -LiteralPath $marker -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture)
            if ([math]::Abs(($previous - $boot).TotalSeconds) -lt 2) { return }   # this boot is already recorded
            $since = $previous
        }
        $state = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).BootupState
        $lines = @(('boot {0:yyyy-MM-ddTHH:mm:ss} {1}' -f $boot, $state))
        foreach ($log in 'System', 'Application') {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2, 3; StartTime = $since } -ErrorAction SilentlyContinue
            $lines += @($events | Sort-Object TimeCreated | ForEach-Object { '  {0:yyyy-MM-ddTHH:mm:ss} {1} {2} {3} {4}' -f $_.TimeCreated, $log, $_.Id, $_.ProviderName, (($_.Message -split "`r?`n")[0]) })
        }
        Add-Content -LiteralPath (Join-Path $run 'boots.log') -Value $lines -Encoding UTF8 -ErrorAction Stop
        Set-Content -LiteralPath $marker -Value $boot.ToString('o', [Globalization.CultureInfo]::InvariantCulture) -ErrorAction Stop
    }
    catch { }
}

function Start-TestRun([string]$Mode, [string]$Root = $script:TestLogRoot) {
    try {
        $run = Join-Path $Root ('{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ($Mode -creplace '[^A-Za-z0-9-]', '-'))
        New-Item -ItemType Directory -Force -Path $run -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath (Join-Path $Root 'current.txt') -Value $run -ErrorAction Stop
        Write-TestStep -Step 'start' -Result 'INFO' -Root $Root
        Save-BootEvents -Root $Root
        $run
    }
    catch { $null }
}
