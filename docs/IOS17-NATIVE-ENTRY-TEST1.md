# iOS 17 native switcher creation experiment

Base: annotated tag `v2.0.5`, source commit `7344d0d`.
Branch: `iya/ios17-native-entry-2.0.5` (local only).
Candidate: `2.0.6-2~native-entry-test1`, with `PACKAGE_VERSION` overriding the
unchanged 2.0.5 control version. This is not a formal release.

## Scope

The user requested a new experiment from 2.0.5, selecting the native iPhone
switcher at creation rather than keeping the later iOS 17 presentation,
transition, Home-floor or cache/query patches. Those later commits are not
ancestors of this branch. The accepted 2.0.5 keyboard, Dock Library and iOS 26
implementation remain the base.

Only iOS 17, the main display scene, TrollPadEx enabled, and the startup iPad
App Switcher choice off take the new path. During the native content-controller
factory, TrollPadEx's temporary iPad idiom counter is suspended and restored in
`@finally`, including when an outer scope already forced iPad or construction
throws. Physical device identity remains native; no iPad is forged as a phone.
Other OS versions, external/unknown scenes, tweak disabled and iPad option on
retain the base factory path.

The complete 2.0.5 constructor and shared compatibility remain unchanged,
including its existing nil `organicExposeAppLayout` compatibility method and
Continuous Expose-to-Deck hook for iPad platform/external roots. The native
main phone root does not select that Continuous Expose root subtree. The
Main-to-Deck factory hook remains confined to iOS 26+ exactly as in 2.0.5.
No later iOS 17 Deck driver, preview cache lease, query bridge, Home floor or
alpha/frame/timing override is introduced. Window management capability/
preferences, keyboard, Floating Dock and Dock Library code are not changed.

## Matching native evidence

21D61 SpringBoard arm64e UUID `7346EBA7-83F7-30E7-9D81-18C47EA290EF`:

- `_loadContentViewControllerIfNecessaryForWindowScene:`, `0x1d37302c0`, ABI
  `v24@0:8@16`, reads raw `switcherStyle` at `0x1d373030c` and selects Deck
  (1), Grid (2), or another debugging controller (3).
- The same factory independently reads UIDevice idiom at `0x1d3730420` and
  chooses `SBiPadOSPlatformSwitcherModifier` for idiom 1/5, otherwise
  `SBFullScreenFluidSwitcherRootSwitcherModifier`.
- Class references: Deck `0x1d8ddb268`, Grid `0x1d8dde520`, iPad platform root
  `0x1d8dde528`, phone root `0x1d8ddcbe0`.
- `SBWindowScene isMainDisplayWindowScene` has ABI `B16@0:8`.
- The iPad platform root's delegate/windowing-mode handling chooses Main or
  Continuous Expose child roots according to Chamois state. Removing that
  platform root may therefore affect real split/window management; keeping
  capability preferences enabled is not proof of runtime coexistence.

## Validation and device acceptance

`test_native_switcher_entry.py` compiles the production idiom, style, creation
scope and presentation-hook startup code with host fixtures for the native
factory's independently decoded decisions. It exercises nested counters,
exception restoration, main/external/unknown scenes, OS/default/hardware
guards, raw/effective style and unchanged window-mode input. The base should
fail the native-phone root selection. This is not execution of Apple's
SpringBoard or proof of actual root selection on the phone.

This experiment is not a claim that the original delayed-entry hitch is fixed.
The phone cannot currently be operated for independent acceptance. No automatic
installation, respring, push, merge to the formal branch or APT publication.

Manual test, after installation, iPad App Switcher OFF and Respring:

1. First minimize and reopen full-screen Apps; verify App/icon animation and
   Dock icons. Stop and retain 2.0.6-1 as rollback if this regresses.
2. Enter/exit the switcher immediately, after 5–8 seconds, and after 20–30
   seconds. Check the first frame, repeated entry and card dismissal.
3. Keep system multitasking settings enabled. Verify actual split view,
   Stage Manager creation/grouping/resizing and Floating Dock in Apps.
4. Re-enable iPad App Switcher and Respring; verify the original grid/window
   path still works. Native-root class metadata can be read later if needed.

Passing the ordinary switcher but losing split view, Stage Manager or Dock is
an experiment failure, not a complete fix or a reason to disable those features.

Both candidate schemes compiled and passed package checks. Their UI/preferences
code sections and 11 Settings/PreferenceLoader resource files per scheme match
formal 2.0.5. All arm64/arm64e slices contain signature load commands, and no
test, probe, diagnostic, symbol or media files are packaged. Signature command
presence is not independent cryptographic/device-loader acceptance. Hashes and
matching symbols are archived locally under ignored release/research paths.
The final functional diff from v2.0.5 is 20 added lines in TweakSB.x; the base
constructor and all existing feature capability/preferences code are unchanged.
