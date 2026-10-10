# iOS 26 Floating Dock follow-up

## Package change

`2.0.1+ios26.1-test3` retains test2's iOS 26 preference fix:
the Settings specifier defaults `TPIsFloatingDockSupported` to YES, but the
SpringBoard observer previously used `boolForKey:`, which returned NO for an
absent key. The observer now uses YES only when this key is absent on iOS 26.
An explicitly saved NO or YES is still honored. The earlier OS branch retains
its original read behavior. Keys, Settings resources and the formal `control`
version are unchanged.

Test3 also checks `FBSSettingForSelector` for the required
`UIMutableApplicationSceneSettings.deactivationReasons` property before forcing
Floating Dock support on iOS 26. If the runtime schema is incomplete, it returns
NO and logs the incompatibility instead of creating a remote Dock that will
assert. The system assertion and scene-settings schema remain intact. This
protects the Dock creation path; it does not make an incompatible backgrounding
module generally safe for every other remote UIKit scene.

`tools/tests/FloatingDockDefaults.m` runs the actual observer in a separate
defaults domain on the VM and verifies missing / explicit NO / explicit YES.
Both package schemes were built sequentially, and their payloads were inspected
for arm64+arm64e, minimum OS 15.0 and valid plists. No VM fixtures or third-party
plugin configuration are included in either DEB.

## vphone crash isolation

The original cold-start crash reaches
`SBFloatingDockRemoteContentManager _setupRemoteContentScene` and then
`FBSMutableSceneSettings addPropagatedProperty:`. The failed property is
`deactivationReasons` on `UIMutableApplicationSceneSettings`; its declaration
exists but `FBSSettingForSelector` returns nil inside SpringBoard.

Controlled isolation on the iOS 26.1 / 23B85 VM found:

| VM configuration | Property registered | Dock cold start |
| --- | --- | --- |
| Original injection set | NO | SIGTRAP / Safe Mode |
| FLEXList alone removed | NO | No change in registration |
| MilkyWay4 and MilkyWay3SubModule removed | YES | Registration restored |
| MilkyWay4 removed, MilkyWay3SubModule restored | NO | Same assertion reproduced |
| MilkyWay4 restored, MilkyWay3SubModule removed | YES | Dock enabled; startup succeeds |

The legacy submodule contains `setDeactivationReasons:` interception. This
is evidence of a conflict in this VM's injection set; it is not a reason to
suppress FrontBoard assertions or alter its scene-settings schema in TrollPadEx.
Experimental schema warming and merging the Dock specification's parent
extensions did not fix this conflict and were not added to production code.

## VM compatibility profile

The VM retains the original plugin binaries. Only
`MilkyWay3SubModule.plist` has a narrower filter: `mediaserverd` remains enabled,
while SpringBoard injection is excluded. MilkyWay4 and FLEXList are restored.
The original filter is backed up on the VM at
`/var/tmp/TrollPadEx-dock-isolation/MilkyWay3SubModule.original.plist` and locally
under `packages/research/ios26.1/`. The profile source is
`tools/vphone/MilkyWay3SubModule.no-springboard.plist` and is never packaged.

Restoring the original filter and reloading SpringBoard restores the original
injection behavior, including the observed conflict on this VM. Reinstalling
the legacy submodule may also restore its original filter.

The separate VRESEARCH-only edge-input fixture remains for synthesized gestures.
Temporary Dock diagnostics are removed after validation. No third-party plugin
is uninstalled, and its preferences are preserved. Restore the original filter
only when deliberately returning to the old injection behavior:

```sh
cp /var/tmp/TrollPadEx-dock-isolation/MilkyWay3SubModule.original.plist \
  /var/jb/usr/lib/TweakInject/MilkyWay3SubModule.plist
sbreload
```

## Validation boundaries

The iOS 26.0.1 / 23A355 IPSW is available locally. Its native windowing and Dock
entry points were inspected; the user subsequently reported that windowing
works after entering the native settings page. There is no local 26.0.1 runtime
test in this follow-up. RootHide is built and inspected, not installed on the
Rootless VM. The reported black window/switcher background is deferred at the
user's request to focus on Floating Dock.

Test2 runtime checks passed with the VM compatibility profile: a missing Dock
preference enabled and created the real remote Dock on cold start; 12 window
resizes changed the actual layout while preserving the SpringBoard PID; after
removing diagnostics, five cycles of opening Calculator and Notes, returning
Home and opening Clock preserved the PID and did not enter Safe Mode. Raw
results are saved under `packages/research/ios26.1/test2-*.json` and
`test2-missing-default-cold-start.txt`.

Test3's negative check restored the original MilkyWay3SubModule filter with the
Dock preference absent (default YES). The captured schema was unregistered,
`dockSupported=0` and `dockCreated=0`; SpringBoard started normally without a
Safe Mode flag. Evidence: `test3-legacy-module-guard.txt`. The VM compatibility
profile is restored after this deliberate test.

Test3's final clean run removed the diagnostic dylib and restored the VM
compatibility profile. Four resize operations changed the observable layout,
and three Calculator + Notes / Home / Clock cycles retained SpringBoard PID
4220 without Safe Mode. The native DockFolderViewService remained running,
and the Dock preference remained absent, exercising the corrected YES default.
Evidence: `test3-clean-regression.json` and `test3-final-device-state.txt`.
Calculator and Notes were reopened afterward.
