# iOS 17 phone switcher candidate

Local branch: `iya/ios17-phone-switcher`, based on formal 2.0.5 (`7344d0d`).
Candidate package: `2.0.6~switcher-test1`. No publication or device installation
is part of this handoff.

## Defect and minimal change

In the iOS 17.3.1 SpringBoard image, UUID
`7346EBA7-83F7-30E7-9D81-18C47EA290EF`,
`-[SBMainSwitcherRootSwitcherModifier _newMultitaskingModifierForEnvironmentMode:]`
at `0x1d34882f8` reads effective switcher style, then tests mode 2 before using
that style. Mode 2 always allocates `SBMixedGridSwitcherModifier`; style 1 only
selects `SBDeckSwitcherModifier` in other modes. The method-list entry confirms
the `@24@0:8q16` signature.

The existing replacement factory already creates the native Deck for mode 2
when TrollPadEx is enabled and the iPad App Switcher option is off. However,
installation was limited to iOS 26+. Extend that installation to exactly iOS 17
while preserving the existing 26+ condition and exact signature/class guards.
iOS 16 and 18 keep their existing paths. The callback, retained return contract,
continuous-Expose factory, iOS 26 window adapter, and settings are unchanged.
The option still takes effect only after respring.

## Regression

`python3.11 -B tools/tests/test_main_switcher_factory.py --baseline-ref 7344d0d`
compiles the production main-factory callback and its actual installation block
in an isolated macOS process, with fixtures representing the native mode-2
behavior above. The old installation fails the iOS 17 phone-card assertion.
The fixed installation passes versions 16/17/18/26/27, master and iPad-option
combinations, other modes, missing Deck/factory classes, and mismatched ABI.
These are production-callback/installation tests with native-path fixtures,
not execution of iOS SpringBoard or proof of on-device rendering.

## Manual acceptance

1. Install the package matching the jailbreak scheme and respring.
2. Turn off **iPad App Switcher**, respring, then open the app switcher. Expect
   horizontally overlapping iPhone cards rather than an iPad grid.
3. Activate an app, return to the switcher, and dismiss a card. Check animation,
   app switching, and clearing the last card without Safe Mode.
4. If Stage Manager is in use, check switching and window resizing there too.
5. Turn **iPad App Switcher** back on and respring. Expect the prior iPad grid.

Physical iOS 17 acceptance is pending. No device IP, input content, or runtime
diagnostic probe is packaged.

Both RootHide and Rootless candidate builds passed. All three packaged binaries
contain arm64/arm64e slices with embedded code-signature commands. The four
Settings resource files are byte-identical to formal 2.0.5; test fixtures and
diagnostic probes are absent. Ignored package metadata and hashes are saved in
`packages/release/ios17-switcher-test1/validation.json`.
