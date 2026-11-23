# TESTLOG (temporary): a log of every setup run for the owner's test runs. Removed after the tests (git grep TESTLOG).
# Each run gets a folder under C:\ProgramData\Cullewie\Logs: steps.log (one line per step), NN-<step>.log (the full
# output of each step) and boots.log (errors and warnings of each boot). current.txt points at the run in progress,
# so the steps after a restart land in the same folder. Nothing here may ever stop the setup: every function swallows
# its own errors.
$script:TestLogRoot = Join-Path $env:ProgramData 'Cullewie\Logs'
$script:TestLogSelf = $PSCommandPath   # this file, for the next-boot entry

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
        # minutes keep counting past an hour (mm:ss alone would show 1 h 05 min as 05:00)
        $length = '{0:00}:{1:00}' -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds
        $line = '{0:yyyy-MM-ddTHH:mm:ss}{1}{2}{1}{3}{1}exit {4}{1}{5}' -f (Get-Date), "`t", $Step, $Result, $ExitCode, $length
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
        $lines += @(Get-NetworkLines)
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

# network state: adapters, IPv4 / gateway / DNS, ping 1.1.1.1, DNS lookup of github.com (one line each)
function Get-NetworkLines {
    $out = @()
    try { foreach ($a in @(Get-NetAdapter -ErrorAction Stop)) { $out += '  net adapter {0}: {1} {2}' -f $a.Name, $a.Status, $a.LinkSpeed } }
    catch { $out += '  net adapter error: ' + $_.Exception.Message }
    try {
        foreach ($c in @(Get-NetIPConfiguration -ErrorAction Stop)) {
            try {
                $ip = @($c.IPv4Address | ForEach-Object { $_.IPAddress }) -join ','
                $gw = @($c.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ','
                $dns = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ','
                $out += '  net ip {0}: {1} gw {2} dns {3}' -f $c.InterfaceAlias, $ip, $gw, $dns
            }
            catch { }
        }
    }
    catch { $out += '  net ip error: ' + $_.Exception.Message }
    $ping = 'FAIL'
    try { if (Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet -ErrorAction Stop) { $ping = 'OK' } } catch { }
    $out += '  net ping 1.1.1.1: ' + $ping
    $dnsOk = 'FAIL'
    try { [void](Resolve-DnsName -Name github.com -DnsOnly -QuickTimeout -ErrorAction Stop); $dnsOk = 'OK' } catch { }
    $out += '  net dns github.com: ' + $dnsOk
    $out
}

# a network check at any moment (e.g. a minute after sign-in, or when the internet wait fails)
function Save-NetworkState([string]$Root = $script:TestLogRoot) {
    try {
        $run = Get-TestRun -Root $Root
        if (-not $run) { return }
        $lines = @(('  net check {0:yyyy-MM-ddTHH:mm:ss}' -f (Get-Date))) + @(Get-NetworkLines)
        Add-Content -LiteralPath (Join-Path $run 'boots.log') -Value $lines -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

# the boot after the last restart runs no setup code: a one-time elevated logon task records it (events, then network
# at sign-in and a minute later) and removes itself. Elevated, because the log folder is for Administrators only.
function Get-NextBootCommand {
    ". '$($script:TestLogSelf -replace "'", "''")'; Save-BootEvents; Start-Sleep 60; Save-NetworkState; Unregister-ScheduledTask -TaskName 'cullewie-nextboot' -Confirm:`$false"
}
function Register-NextBootLog {
    try {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-NextBootCommand)))
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'cullewie-nextboot' -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
    }
    catch { }
}
