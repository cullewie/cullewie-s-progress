# Game Pass option (short design)

Date: 2026-11-23. Approved by the repo owner in conversation.

## Intent
People who play through Game Pass Ultimate (the owner's friend, for example) need the Xbox app, Gaming Services and Microsoft Store downloads to work. Today the setup breaks those, even though the Tweaks.ps1 header says they are kept. Services.ps1 disables wuauserv, UsoSvc, WaaSMedicSvc, BITS, XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc and iphlpsvc. Tweaks.ps1 unbinds IPv6, removes the Game Bar, and turns off Store auto-update and background apps.

## Update (same day): three levels instead of one switch
The owner asked for a "Store only" choice next to Xbox. The choice is now `-Apps off|store|xbox`; the default is off, which is today's behaviour.
- **store:** Store downloads, installs and updates work.
  - Services set to Windows defaults: wuauserv, BITS, UsoSvc, WaaSMedicSvc, PushToInstall.
  - Tweaks keeps Store auto-update and background apps.
  - The monthly-only Windows Update policy is applied.
- **xbox:** everything in store, plus the Xbox services (XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc), iphlpsvc (Teredo), GameInputSvc, WpnService and WpnUserService.
  - Tweaks also keeps GameInput, the Game Bar and IPv6.
- The Launcher question: "Microsoft Store / Xbox kullaniyor musunuz? 1 = Hayir, 2 = Sadece Microsoft Store, 3 = Xbox ve Game Pass (Store dahil)". Live mode uses `CULLEWIE_APPS=store|xbox`.
- Services are written at their Windows default values rather than left out of the list, so a PC that was already stripped gets them back.
The goals below describe the xbox level.

## Goals
- One Launcher option, off by default, labelled: "Xbox hizmetlerini ve Microsoft Store'u kullaniyorsaniz bunu secin (Game Pass)".
- When it is on:
  - Xbox, Gaming Services, Store install/licensing, BITS, DoSvc and iphlpsvc (Teredo) services stay at their Windows defaults.
  - Windows Update stays on, but gets only the monthly cumulative update: the feature release is pinned (TargetReleaseVersion), and driver and preview updates are off.
  - Tweaks keeps IPv6, the Game Bar, Store auto-update and Xbox background activity.
- When it is off: behaviour is identical to today's release.

## Non-goals and anti-goals
- No separate edition or duplicated scripts.
- Windows 11 has no security-only channel, so we do not claim one. "Security only" here means the monthly cumulative update with nothing else.
- Failure even if it "works": Store or Xbox sign-in broken, Game Pass installs failing with 0x80070422, or the default (option off) path changing.

## Approaches
1. **One option through the shared scripts (chosen):** the Launcher passes a flag, and Services.ps1 and Tweaks.ps1 skip or adjust the Store/Xbox/Update parts. This keeps one code path.
2. A separate Game Pass setup: rejected because it duplicates files and the hashes in manifest.json.
3. Make the default Game Pass-friendly: rejected because users who don't use Game Pass want today's stripped setup.

## Constraints
- Files are byte-pinned (`* -text`, LF), and the release flow is: payload commit, then update manifest.json, then a "Pin bootstrap" commit.
- Test statically first: a parser check and the Services dependency check, extended to cover both option states. A live test on the owner's PC happens only after the review/fix loop is clean, and only in `live` mode.

## Left to the builder
How the flag travels: a Launcher menu prompt, a resume-task argument and child script parameters. It must survive the safe-mode resume. Also left to the builder: the exact list of services and keys to keep, and the Windows Update policy values.
