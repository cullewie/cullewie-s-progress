# Store / Xbox Option Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in choice with three levels: off, store and xbox. Store keeps Microsoft Store downloads working. Xbox keeps the Store plus the Xbox app, Gaming Services and Xbox networking. Both get only the monthly cumulative Windows update.

**Architecture:** `-Apps off|store|xbox` is a parameter on `Services.ps1` and `Tweaks.ps1`. The Launcher decides it once:
- **Full mode:** it asks at the start and stores the answer in a flag file, which survives the safe-mode reboots.
- **Live mode:** the value comes from `-Apps` or from `CULLEWIE_APPS`.

`Services.ps1` writes the planned Start values of the kept services at their Windows defaults, so a PC that was already stripped gets them back. `Tweaks.ps1` skips the steps that would break the chosen level and sets a Windows Update policy.

**Tech Stack:** Windows PowerShell 5.1 and .reg text. Tests are plain PowerShell assertions, without Pester.

**Spec:** `docs/superpowers/specs/2026-11-23-game-pass-option-design.md`. Read the "Update (same day)" section, which replaces the single switch.

## Global Constraints

- **Windows PowerShell 5.1.** Every repo script must parse with `[System.Management.Automation.Language.Parser]::ParseFile`, and so must the scripts generated from the Services and Defender here-strings.
- **Byte-pinned files (`* -text`).** These stay CRLF: IWR.ps1, Scripts/GPU/DDU.ps1, Scripts/NVIDIA/Settings.ps1, Scripts/Windows/Timer-Resolution.ps1 and manifest.json. Everything else stays LF. Check with `git ls-files --eol`.
- **Launcher question, verbatim:** `Microsoft Store / Xbox kullaniyor musunuz? 1 = Hayir, 2 = Sadece Microsoft Store, 3 = Xbox ve Game Pass (Store dahil)`. `2` means store, `3` means xbox, and anything else means off.
- **Off level:** behaviour is identical to today's release, with the same 248-entry service plan.
- **Live mode** never asks a question.
- **Aggressive settings stay.** Only the items listed here change, and only for the chosen level.
- **Release flow:**
  1. Payload commit.
  2. Update manifest.json size and sha256.
  3. A "Pin bootstrap" commit that sets `$PayloadCommit` and `$ExpectedManifestSha256` in IWR.ps1.
  4. Push only after the owner says yes.
- **Development is static.** Tests are read-only, apart from `HKCU:\Software\ClaudeAppsTest` and temp files. Never run the full Tweaks, Services, Launcher or IWR on this PC; the only exception is `Services.ps1 -PlanOnly`, which must change nothing.

**Service defaults (exact):**
- **store:** `wuauserv=3, BITS=3, UsoSvc=2, WaaSMedicSvc=3, PushToInstall=3`
- **xbox:** the store set plus `XblAuthManager=3, XblGameSave=3, XboxGipSvc=3, XboxNetApiSvc=3, iphlpsvc=2, GameInputSvc=3, WpnService=2, WpnUserService=2`

**Tweaks per level:**
- **store and xbox:** skip the `GlobalUserDisabled` and `LetAppsRunInBackground` Set-Reg calls, remove the three `$controlPanel` key blocks (WindowsStore\WindowsUpdate, Policies\...\AppPrivacy, BackgroundAccessApplications), and run `Set-AppsUpdatePolicy`.
- **xbox only:** also skip the GameInput MSI removal and the whole Game Bar block (overlay removal, the `gamebaroff` import, the PresenceWriter Run-Trusted), and keep `ms_tcpip6` bound.

## Review Focus

1. **The off level changes nothing.** The plan still has 248 entries, and BITS, wuauserv and XblAuthManager are still 4 (Task 1, `Off-PlanUnchanged`).
2. **Elevation relaunch.** It must forward `-Apps`, which is the same kind of bug as the old dropped `-Live` (Tasks 1 and 2, `*-RelaunchForwardsApps`).
3. **Store level leaves Xbox alone.** XblAuthManager stays 4 and the Game Bar block still runs (Task 1 `Store-PlanSetsDefaults`, Task 2 `Tweaks-Guards`).
4. **Stale choice from an earlier run.** `Start-FullSetup` deletes the old flag before it asks, and `Resume-FullSetup` only reads it (Task 3, `Launcher-FlagLifecycle`).
5. **A bad value in the flag or the environment** (`STORE`, empty, `abc`). Case-insensitive store/xbox values work; anything else means off. There is no crash under StrictMode (Task 3, `Launcher-AppsValue`).

---

### Task 1: Services.ps1 `-Apps` and `-PlanOnly`

**Files:**
- Modify: `Scripts/Windows/Services.ps1`:
  - the param line
  - the relaunch at line 5
  - right after the `$ServicesOff = @'...'@` assignment
  - right after the dependency-check conflict branch
  - the generated script's read-back
  - the header comment
- Create: `Tests/Apps.Tests.ps1` (shared; later tasks append to it)

**Interfaces:**
- Produces:
  - Params `[ValidateSet('off','store','xbox')][string]$Apps = 'off'`, `[switch]$PlanOnly`, `[string]$PlanPath = "$env:ProgramData\Cullewie\Work\services-plan.txt"`.
  - `-PlanOnly` writes the final `$ServicesOff` to `$PlanPath`, then exits 0. When the check finds conflicts, the existing conflict branch exits 1 before that. `-PlanOnly` never reaches RunOnce, bcdedit, reg import or a restart.
  - `Set-ServiceStartInText([string]$Text, [hashtable]$Start) -> [string]` replaces the 8-digit value after `[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\<name>]` + newline + `"Start"=dword:`. Matching is case-insensitive.
  - `Get-AppsServiceStart([string]$Apps) -> [hashtable]` returns the store or xbox default map from Global Constraints, or an empty map for off.

- [ ] **Step 1: Write the failing tests** in `Tests/Apps.Tests.ps1`.
  - Helpers:
    - `Assert($cond, $name)` prints PASS or FAIL and counts failures.
    - `Get-Plan($path)` returns a name -> int map, using the dependency-check regex `(?m)^\[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\([^\]]+)\]\r?\n"Start"=dword:0*(\d)`.
    - The script ends with `exit $failures`.
  - Tests:
    - `Off-PlanUnchanged`: `Services.ps1 -PlanOnly -PlanPath $tmp` exits 0, there are 248 entries, and BITS, wuauserv and XblAuthManager are all 4.
    - `Store-PlanSetsDefaults`: with `-Apps store` the run exits 0. The 5 store names have exactly their defaults, XblAuthManager stays 4, and there are 248 entries.
    - `Xbox-PlanSetsDefaults`: with `-Apps xbox` the run exits 0. All 13 names have their defaults, DiagTrack stays 4, and there are 248 entries.
    - `Services-RelaunchForwardsApps`: the first `Start-Process PowerShell.exe` line contains `$Apps`.
    - `Services-Parses`: the outer file and the generated script both have 0 parse errors.
- [ ] **Step 2: Run the tests and watch them fail.** From an elevated shell run `powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Apps.Tests.ps1`. Expected: FAIL `Off-PlanUnchanged`, because `-PlanOnly` doesn't exist yet.
- [ ] **Step 3: Implement.**
  - Add the params. The relaunch forwards `-Live` and `-Apps $Apps`.
  - After the here-string: `$ServicesOff = Set-ServiceStartInText $ServicesOff (Get-AppsServiceStart $Apps)`. With an empty map it returns the same text.
  - After the conflict branch: `if ($PlanOnly) { Set-Content $PlanPath $ServicesOff; exit 0 }`.
  - The generated read-back also writes a non-empty `$notApplied` to `$env:ProgramData\Cullewie\Work\services-not-applied.txt`.
  - Add one header line per level.
- [ ] **Step 4: Run the tests and watch them pass.** Expected: all PASS, exit 0.
- [ ] **Step 5: Commit.** `git add Scripts/Windows/Services.ps1 Tests/Apps.Tests.ps1`, then `git commit -m "Services: -Apps store|xbox sets the services they need to Windows defaults; -PlanOnly"`.

### Task 2: Tweaks.ps1 `-Apps`

**Files:**
- Modify: `Scripts/Windows/Tweaks.ps1`:
  - the param at line 19
  - :91 GameInput
  - :192-194 background apps
  - :370-411 the Game Bar block
  - before the `controlpanel` import at :1377
  - the binding list at :1432
  - the header, lines 1-17
  - the end of the file
- Test: `Tests/Apps.Tests.ps1` (append)

**Interfaces:**
- Consumes: the test helpers from Task 1.
- Produces:
  - Param `[ValidateSet('off','store','xbox')][string]$Apps = 'off'` (keeps `-DryRun`).
  - `Remove-RegKeyBlock([string]$Text, [string]$Key) -> [string]` removes the `[<Key>]` line and its value lines, up to and including the next blank line. Matching is case-insensitive.
  - `Set-AppsUpdatePolicy([string]$PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', [string]$UxKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings', [string]$DisplayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion)`, using `Set-Reg`. It writes:
    - under PolicyKey: `TargetReleaseVersion=1` (DWord), `ProductVersion='Windows 11'` (String), `TargetReleaseVersionInfo=$DisplayVersion` (String), and `ExcludeWUDriversInQualityUpdate=1`, `AllowOptionalContent=0`, `SetAllowOptionalContent=0` (DWord)
    - under UxKey: `IsContinuousInnovationOptedIn=0` (DWord)

- [ ] **Step 1: Write the failing tests** (append):
  - `Tweaks-Guards` (AST):
    - The `GlobalUserDisabled` and `LetAppsRunInBackground` Set-Reg calls are inside an `if` whose condition text is `$Apps -eq 'off'`.
    - The GameInput `Remove-MsiProduct`, the XboxGamingOverlay `Remove-AppxPackage`, `Import-Reg 'gamebaroff'` and the PresenceWriter `Run-Trusted` are inside an `if` whose condition text is `$Apps -ne 'xbox'`.
  - `Tweaks-RemoveRegKeyBlock`: extract the function and the `$controlPanel` value through the AST. Removing the 3 keys removes `AutoDownload`, `LetAppsRunInBackground` and `GlobalUserDisabled`, while `LongPathsEnabled` and `IsPrelaunchEnabled` stay.
  - `Tweaks-UpdatePolicy`: extract `Set-Reg` and `Set-AppsUpdatePolicy`, then call the function with `-PolicyKey HKCU:\Software\ClaudeAppsTest\WU -UxKey HKCU:\Software\ClaudeAppsTest\UX -DisplayVersion 25H2`. Read back all 7 values with their types, then delete the key.
  - `Tweaks-BindingList`: the binding list expression references `$Apps`, and in memory it gives the list without `ms_tcpip6` for xbox and with it for store and off.
  - `Tweaks-RelaunchForwardsApps`: if Tweaks has a `Start-Process` relaunch, it contains `$Apps`. If there is none, the test passes.
  - `Tweaks-Parses`: 0 parse errors.
- [ ] **Step 2: Run the tests and watch them fail.** Expected: FAIL `Tweaks-Guards`.
- [ ] **Step 3: Implement.**
  - Add the param and the guards as listed in "Tweaks per level".
  - Before the controlpanel import: `if ($Apps -ne 'off') { foreach ($k in <3 keys>) { $controlPanel = Remove-RegKeyBlock $controlPanel $k } }`.
  - Binding list: `@('ms_lldp','ms_lltdio','ms_implat','ms_rspndr') + @(if ($Apps -ne 'xbox') { 'ms_tcpip6' }) + @('ms_server','ms_msclient','ms_pacer')`.
  - Before the exit lines: `if ($Apps -ne 'off') { Write-Host 'Store/Xbox: Windows Update gets the monthly update only'; Set-AppsUpdatePolicy }`.
  - Header: one line per level.
- [ ] **Step 4: Run the tests and watch them pass.** Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "Tweaks: -Apps store keeps Store auto-update and background apps, xbox also GameInput, Game Bar and IPv6; monthly-only Windows Update"`.

### Task 3: Launcher and IWR carry the choice

**Files:**
- Modify:
  - `Launcher.ps1`: the param block, the start of `Start-FullSetup`, the tweaks and services calls in `Resume-FullSetup`, and the tweaks and services calls in `Start-LiveSetup`
  - `IWR.ps1:159-163` (CRLF)
  - `README.md`: a short Turkish section
- Test: `Tests/Apps.Tests.ps1` (append)

**Interfaces:**
- Consumes: `-Apps` on Services.ps1 (Task 1) and Tweaks.ps1 (Task 2).
- Produces:
  - Param `[string]$Apps = ''` (empty means "ask" in full mode).
  - `$script:AppsFlag = "$env:ProgramData\Cullewie\Work\apps.flag"`, which holds `store` or `xbox`.
  - `ConvertTo-AppsLevel([string]$Value) -> [string]`: a trimmed, case-insensitive `store` or `xbox` gives that value; anything else gives `off`.
  - `Get-AppsArguments -> [string[]]`: returns `@('-Apps', <level>)` from the flag file, or `@()` when there is no flag or the level is off.
  - `Read-AppsChoice -> [string]`: if `$Apps` is set, it returns `ConvertTo-AppsLevel $Apps`. Otherwise it shows the verbatim question and maps `2` to store, `3` to xbox, and anything else to off.
  - IWR passes `-Apps $env:CULLEWIE_APPS` when that variable is set.

- [ ] **Step 1: Write the failing tests** (append):
  - `Launcher-FlagLifecycle` (AST):
    - In `Start-FullSetup`, removing `$script:AppsFlag` comes before the `Read-AppsChoice` call, and that call comes before the first `Invoke-RequiredTool`.
    - `Resume-FullSetup` has no `Read-AppsChoice`.
    - The tweaks and services invocations in `Resume-FullSetup` and `Start-LiveSetup` contain `Get-AppsArguments`.
  - `Launcher-LiveNoPrompt`: `Start-LiveSetup` contains no `Read-Host` and no `Read-AppsChoice`. It sets or deletes the flag from `ConvertTo-AppsLevel $Apps`.
  - `Launcher-AppsValue`: extract `ConvertTo-AppsLevel` and run it under `Set-StrictMode -Version Latest`. Expected results: `'store'` gives store, `'XBOX '` gives xbox, and `''`, `$null` and `'abc'` give off.
  - `Launcher-Question`: the file contains the verbatim question.
  - `IWR-ForwardsApps`: the file contains `CULLEWIE_APPS` and `-Apps`, and is still CRLF only.
  - `Launcher-Parses`: 0 parse errors.
- [ ] **Step 2: Run the tests and watch them fail.** Expected: FAIL `Launcher-FlagLifecycle`.
- [ ] **Step 3: Implement.**
  - Full mode: delete the flag, ask, and write the flag unless the answer is off.
  - Resume: tweaks gets `(Get-AppsArguments)`, and services gets `@('-Live') + (Get-AppsArguments)`.
  - Live: write or delete the flag from `$Apps`, then pass the same arguments.
  - IWR: add the argument.
  - README: 3-5 Turkish lines covering the levels, `CULLEWIE_APPS`, and that "only security" means the monthly cumulative update.
- [ ] **Step 4: Run all the tests and watch them pass.** Expected: all PASS, exit 0.
- [ ] **Step 5: Commit.** `git commit -m "Launcher: Store/Xbox question in full setup, -Apps/CULLEWIE_APPS for live; README"`.

### Task 4: Release

- [ ] **Step 1:** Run the parse check on every .ps1 and the generated scripts, then `Tests\Apps.Tests.ps1`, then `git ls-files --eol`. Expected: 0 errors, exit 0, and the line endings listed in Global Constraints.
- [ ] **Step 2:** Update the size and sha256 for every manifest.json entry, keeping the CRLF line endings and the layout. Expected: 0 mismatches.
- [ ] **Step 3:** Commit `Release: Store/Xbox option`. Then set `$PayloadCommit` and `$ExpectedManifestSha256` in IWR.ps1 and commit `Pin bootstrap`.
- [ ] **Step 4:** Ask the owner before `git push origin main`.
