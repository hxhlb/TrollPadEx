# Keyboard nine-key test1 / test2

## Test2 correction (2026-10-22)

The user reported that test1 still showed a full keyboard in portrait Safari
and Messages, with nine-key absent from the selectable list. A standalone
read-only native probe confirmed that the saved AppleKeyboards array already
includes `zh_Hans-Pinyin@sw=Pinyin10-Simplified`; native Phone and Pad layout
candidates both contain `Pinyin10-Simplified` on this iOS 17.3.1 device.

A separate read-only Mach probe inspected only loaded image metadata and the
known test1 library globals, without injecting a script, suspending a process,
or reading text. Matching the loaded UUID against the local arm64e dSYM proved
that Safari and SpringBoard both loaded test1. Both idiom hooks had original
function pointers installed. However, Safari held `enableiPadKeyboard=YES`
while SpringBoard held `NO`, despite the shared plist explicitly storing false.
This establishes a process-specific preference-read failure ahead of the idiom
fix. The test1 callbacks were present but continued to use the iPad path.

Test2 reads the shared `com.kdt.trollpad.plist` snapshot before consulting
CFPreferences. RootHide resolves this path through `jbroot`; other packaging
keeps the normal mobile preferences path. Missing file/key values retain the
existing CFPreferences fallback and defaults. Reads occur at startup and upon
preference notifications, not on individual keystrokes. No preferences are
written or input modes forcibly selected.

The regression harness now covers sandbox CFPreferences missing the domain,
with shared-file cold-start off/on settings, authoritative saved false,
master-off snapshots, and missing-key defaults. The new sandbox-off case failed
against test1 before this correction; all fixed callback cases now pass.
The user subsequently confirmed that portrait Safari nine-key appeared with
test2 and the iPad keyboard option off. The read-only image/global probe also
confirmed Safari, Preferences, and SpringBoard all held `enableiPadKeyboard=NO`
under the matching test2 UUID. This closes the observed Safari preference-read
regression. Messages, orientation transitions, and other OS versions remain
outside this physical-device confirmation.

Both RootHide and Rootless test2 packages built successfully with unchanged
Settings resources and no probes/test fixtures packaged. The RootHide package
was installed and `/usr/bin/sbreload` completed. SpringBoard loaded the matching
test2 UUID and reports the saved keyboard option off. Safari runtime state and
user rendering feedback both passed after reopening the app.

## Scope

Based on released `TrollPadEx` commit `b24575a`, isolated on local branch
`codex/keyboard-nine-key`. The existing Dock Library development checkout is
untouched. This beta changes keyboard idiom handling only; it does not change
windowing, keyboard selection, orientation, settings resources, or frame rate.

When TrollPadEx is enabled, the iPad keyboard option is off, and the hardware is
an iPhone/iPod touch, restore Pad keyboard idioms to Phone. Other idioms, real
iPads, master-off behavior, and the enabled iPad keyboard behavior are preserved.

`UIKeyboardGetSafeDeviceIdiom` now participates even when the keyboard option is
off at process startup. The independent `UIKBScreenTraits -idiom` path is hooked
only when its runtime signature matches `q16@0:8`. Preference changes reload the
active first responder's input views on the main thread; background applications
defer that refresh until activation. Private object getters are signature checked.

## Evidence and validation

- Static UIKit inspection: iOS 17.3.1 and 26.0.1 have independent device-idiom
  and screen-trait paths. Keyboard factories use the latter.
- Native UIKit on the retained iOS 18.6 simulator exposes
  `Pinyin10-Simplified` for both Phone and Pad candidate lists. No software-layout
  list filtering hook was added.
- Regression command:
  `python3.11 tools/tests/run_keyboard_tests.py --baseline-ref b24575a`
- The actual production Logos callbacks were exercised inside standalone test
  processes: old code fails the cold-start-off case; fixed cold-start-off and
  cold-start-on cases pass. Policy cases include toggles, master off, iPad
  hardware, and preserving non-Pad idioms. These are isolated callback tests,
  not physical keyboard rendering proof.
- Rootless and RootHide packages built sequentially for
  `2.0.3+keyboard-test1`. Both contain arm64/arm64e slices, unchanged Settings
  resources, and no test fixtures. Digests are recorded in the ignored
  `packages/release/keyboard-test1/package-validation.json` artifact.

## Physical-device status

On 2026-10-22, with explicit user approval, installed the RootHide beta on the
user's iPhone 15 Pro running iOS 17.3.1, then invoked `/usr/bin/sbreload`.
Package status confirms `2.0.3+keyboard-test1`; SpringBoard PID changed from
29229 to 29401. No checked Safe Mode flag was present after restart.
The existing keyboard preference remained off; preferences were not rewritten.

Actual Safari nine-key rendering still requires the user's manual check.
An earlier Frida attach ended before script loading and Safari exited;
no keyboard snapshot was collected and no further attachment was attempted.

## Remaining boundaries

- iPad keyboard enabled plus nine-key hybrid behavior is not implemented.
- Other users' missing split-view keyboard and approximately 80 FPS reports
  are unverified; this beta does not change keyboard focus or rendering limits.
- No merge, push, or APT publication is part of this beta.
