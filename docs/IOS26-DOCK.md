# iOS 26 Floating Dock follow-up

Release status: the maintainer accepted iOS 26 support after identifying the
KillBackground13 content-query interception. Formal 2.0.3 preserves the functional
Dock changes and removes the temporary diagnostic switch, export UI and sampler.
The reports below are historical evidence, not current diagnostic instructions.

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

## In-app gesture recovery (scale-test6)

This candidate includes test5's iOS 26.0.1 legacy switcher correction and an
iOS-26-only recovery for a hidden, ready Dock whose active app-level assertion
denies gesture tracking. It hooks `SBFloatingDockBehaviorAssertion.gesturePossible`
on the active assertion, which feeds both legacy and modern Dock gestures.
An already-allowed native query returns unchanged. Recovery requires the main
display, application layout mode, no visible switcher or keyboard, available
protected data, a valid hidden Dock with ready remote content, and native
behavior level 9 denying gestures. Other behavior levels retain native policy.
No new gesture recognizer or forced Dock presentation is added. The native
gesture still controls animation, progress, completion and dismissal.

The application mode comes from `SBSwitcherController.unlockedEnvironmentMode`:
Apple's mode labels are 0 undefined, 1 Home, 2 switcher, 3 application in both
26.0.1 and 26.1. `SBFluidSwitcherViewController.environmentMode` is a fixed-zero
base implementation and cannot be used for this check. All 15 required method
signatures match the 23A355 IPSW and the 26.1 runtime; an incomplete runtime does
not install the recovery hook. Earlier OS versions, the master-off path and a
disabled Floating Dock preference retain the previous behavior.

Without fault injection, the 26.1 VM already reveals its native Dock after a
window is resized over it, with both iPhone and iPad switcher presentations.
The physical user's failure and its precise cause have not been reproduced.
The recovery therefore targets the denied in-app gesture state explicitly;
it does not repair an absent Dock controller, an unavailable remote scene or a
third-party scene-schema conflict. The existing creation safety guard remains.
Automatic hiding was not enabled for these tests: the temporary
`SBChamoisHideDock` probe value was deleted, restoring its absent-key state.

A reversible VM-only fixture denied gestures on the active level-9 assertion.
Without recovery, Stage Manager left the Dock hidden and Windowed Apps entered
the switcher instead of revealing the Dock over the app. With production
recovery enabled, both modes revealed the Dock while remaining in application
mode 3, retaining SpringBoard PID 25598. The fixture restored its changed field
and was removed before subsequent cold-start tests. Evidence:
`dock-test6-fault-results.json` and `dock-test6-*-context.json`. This proves the
targeted recovery, not the cause of the physical user's Dock failure.


## Combined clean regression (scale-test14)

The final package retains this gesture recovery together with the phone-switcher
context/copy repair described in `SWITCHER.md`. On the observer-free 26.1 VM,
Notes grew over the Dock in Windowed Apps and shrank/grew in Stage Manager. The
Dock was hidden when covered, and a short bottom-edge swipe revealed it over
the still-open app in both modes. SpringBoard remained PID 29598 with no Safe
Mode; `SBChamoisHideDock` remained absent. This normal-path regression does not
replace the earlier denied-gesture fault test or prove the physical user's cause.
Evidence: `dock-test14-windowed-result.json`, `dock-test14-stage-result.json`
and covered/revealed screenshots in the local research directory.

## Physical follow-up and native comparison (2026-10-12)

The tester still reports no Dock inside apps in either Stage Manager or Windowed
Apps, even with a centered window and Floating Dock enabled. This is not limited
to recovering a Dock covered by a resized window. Test14's VM results therefore
do not establish a fix for the reported physical-device failure.

The local 26.0.1 / 23A355 images were compared with recorded 26.1 / 23B85 runtime
instructions. The reachable entry-function paths agree for the inspected Dock
support query, window-scene controller lookup, remote-scene setup, controller
registration, gesture permission and Home-gesture start. Matching selector
sequences establish the inspected call paths, not identical runtime state.
Local evidence: `packages/research/ios26.0.1/dock-followup-selector-comparison.json`.
The truncated active-assertion capture and an unresolved 26.1 constructor target
are excluded from conclusions about differences.

Both versions' native
`_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:`
include an app-hidden Dock assertion at level 9 with `gesturePossible=YES`, and
an overlay assertion at level 6 with gestures allowed. The inspected native
Deck, legacy continuous Expose and modern Expose personalities all return NO
from `shouldConfigureInAppDockHiddenAssertion` on 26.0.1. There is no evidence
here that 26.0.1 simply lacks in-app Dock support or that changing the switcher
personality's constant alone repairs this report.

The creation guard is a separate diagnostic gate. The 23A355 FrontBoardServices
image exports `FBSSettingForSelector`, and both application scene-settings
classes implement `deactivationReasons`. Their presence does not prove that the
property is registered inside the tester's injected SpringBoard process. The
VM's earlier legacy-submodule conflict is not evidence of the same conflict on
this phone. The guard remains intact; disabling it could restore the known
remote-scene assertion instead of creating a usable Dock.

The remaining distinction requires device state: whether the Dock controller
exists, its remote content is ready, scene-schema registration succeeds, and
which assertion/gesture gate is active. A tester comparison with iPad App
Switcher enabled and a respring has been requested; its result is pending.
No additional force-presentation hook or auto-hide preference is added from
this static comparison. Merge/publication remains pending this Dock follow-up.

## Diagnostic candidate (scale-test15)

Adds default-off, iOS-26-only state/gesture logging and export to Files. See
[the historical collection procedure and privacy/size bounds](research/DOCK-DIAGNOSTICS.md).
This candidate observes the unresolved physical-device failure; it does not add
another Dock recovery policy or claim the failure is fixed.

The standalone contract passed on the Rootless 26.1 VM, covering unknown values,
missing/unready/denied/allowed states, already-presented Dock policy, disabled
no-op, bounded rotation and complete JSONL records. A default-off cold start did
not create a log. Enabling through Settings recorded controller/remote/assertion
state and native Dock gesture entries; disabling stopped writes. Export to Files
saved a byte-identical 56,291-byte report. The initial UIActivityViewController
experiment asserted inside native collection layout in both windowed and full
screen settings; it was replaced with UIDocumentPickerViewController and is not
the shipped export path. These failed export experiments crashed Settings,
not SpringBoard. RootHide retains build/package coverage only.

The final candidate cold-started at PID 36262 with logging disabled; its existing
report remained byte-for-byte unchanged. Opt-in recording then sampled both
window-mode preferences and native gesture entries without changing that PID or
entering Safe Mode. The Stage Manager sample was in application mode 3; the
Windowed sample was in switcher mode 2 and does not establish in-app Dock reveal.
Live disable stopped writes. The VM was restored to iPad switcher on, Windowed
Apps, diagnostics off, and an absent auto-hide preference. Evidence:
`dock-test15-final-runtime.json`, `dock-test15-final-runtime.log` and
`dock-test15-export-result.json` under the local research directory.

## First physical diagnostic report (2026-10-12)

The tester's format-1 report contains 59 complete records from 26.0.1 / 23A355.
All three sessions use the iPhone Deck (`appliediPadSwitcher=false`). In 29
application-mode samples spanning both Stage Manager preference values, the
Dock exists, remote content is ready, and the active level-9 assertion and
controller allow gestures, but `contentGesturePossible=false`. The observed
content query returns NO and the Dock gesture-start method returns nil. This
narrows the failure to the content query/lookup path; the earlier level-9
permission recovery does not address that sampled state.

The matching IPSW's `SBFluidSwitcherViewController.isFloatingDockGesturePossible`
only resolves `_floatingDockController` and reads its `isGesturePossible`.
Its controller lookup uses `_sbWindowScene`, supplied by
`dataSource.windowSceneForSwitcherContentController:`. The report does not record
those intermediate objects, so a nil/different controller and an intercepted
query remain separate hypotheses. The saved auto-hide preference is YES in this
report; that configuration difference alone does not explain the conflicting
permission queries and is not changed by diagnostics. The three PID changes
without crash reports do not establish Safe Mode or a crash.

Candidate `2.0.2+scale-test16` adds format-2 lookup identity/availability and
implementation-image evidence, with no Dock policy change. Both package schemes
pass build/payload checks. A Rootless 26.1 phone-Deck cold start at PID 45801
captured matching content/data-source/main scenes and Dock controllers, native
SpringBoard implementation images, ready remote content, and no Safe Mode.
This validates the observer, not the physical failure. The tester was asked to
enable iPad App Switcher and respring with the existing candidate first. The
second report below completes that comparison; the extended candidate is now
ready for a short lookup-trace test.

## Second physical diagnostic report (2026-10-12)

The second format-1 export contains 263 complete records and retains the first
report's sessions. The latest session, PID 9772, confirms desired/applied iPad
switcher YES and `SBGridSwitcherViewController`. In Windowed Apps, 12
application-mode samples still show a ready Dock and allowed level-9/controller
gestures while the content query denies them. Switching back to the iPad grid
therefore does not eliminate this sampled discrepancy. It is not confined to
the newly added phone-Deck path.

The 108 missing-Dock/support-denied records in intermediate sessions all have
`masterEnabled=false`; those are not evidence of a Dock creation failure with
the tweak enabled. In the latest enabled session, three observed Dock gesture
starts occur with a denying level-12 assertion. That is additional policy
evidence, not authorization to override all levels. The level-9 query discrepancy
and the level-12 denials must remain distinguishable.

Format 1 does not identify whether the content query uses the main scene's Dock
or an intercepted lookup. Format-2 test16 is provided for a short test with the
current switcher choice: install/respring, ensure diagnostics are enabled, open
one app in Windowed Apps and attempt the reveal two or three times, then disable
and export. A full two-mode test cycle is not required for this next distinction.
No functional Dock policy is changed. Local analysis evidence:
`packages/research/ios26.0.1/physical-dock-test15-second-log-analysis.json`.

## Third physical diagnostic report: intercepted content query

The third export contains 577 complete records, including a format-2 session at
line 376 / PID 9942. Before the observer installed, the implementation image for
`SBFluidSwitcherViewController.isFloatingDockGesturePossible` was
`KillBackground13.dylib`. Other observed gesture entries and the content/Dock/
data-source scene lookups resolve to SpringBoard. The current content-query
implementation is `TrollPadSB.dylib` because it is the diagnostic wrapper; its
recorded pre-observer implementation identifies the upstream interception.

All 200 format-2 state records show the content scene, data-source scene and
content Dock matching the main scene and its Dock. In 37 ready application-mode
samples, querying that same Dock directly permits gestures, while the wrapped
content query returns NO. This excludes the nil/different-controller hypothesis
for those samples and strongly points to the intercepted content query. Both
the iPad Grid and phone Deck reports have shown the upper-query denial.

The next comparison is to temporarily disable KillBackground13 injection into
SpringBoard, respring, and repeat the short Dock test with the same test16
package and other settings unchanged. No new package or blanket gesture
override is required for this comparison. The report also contains level-12
native policy denials; it does not prove they all originate from the same tweak
or justify overriding them. A successful single-tweak comparison is still needed
before declaring the entire physical Dock failure resolved.

Local evidence:
`packages/research/ios26.0.1/physical-dock-test16-third-log-analysis.json`.
