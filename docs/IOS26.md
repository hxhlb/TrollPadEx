# iOS 26 support

Branch: `ios26-support`. Latest local test package: `2.0.1+ios26.1-test3`.
The release version in `control` remains `2.0.1`; nothing has been published.
Test2's default-value correction and the VM's legacy-plugin crash isolation
are documented in [IOS26-DOCK.md](IOS26-DOCK.md). The checks below describe the
original test1 windowing validation.

## Native implementation

iOS 26 uses a window management context and flexible windowing modifiers.
`TweakSB.x` enables the native capability checks, supplies the raw grid switcher
style required by the controller factory, and allows resizing in Windowed Apps
as well as Stage Manager. The native settings continue to choose the mode.

The side and mirror preferences target the new modifier classes. The
`frameForItem:` hook checks its 96-byte aggregate return signature before
installation. Changing the side or master switch rebuilds the system's cached
gesture recognizers using the current window management context.

All new hook groups and capability function hooks require iOS 26 or later.
Below iOS 26, the four updated resizing call sites return their previous
Stage Manager predicate. The iOS 18 settings hooks, preference keys, defaults,
localizations, `TweakUI.x`, and package layout configuration are unchanged.

## Validation on vphone

Environment: iOS 26.1 / 23B85, VRESEARCH kernel, Rootless, arm64e system.
Both tweak dylibs contain arm64 and arm64e slices, with deployment target 15.0.

| Check | Result |
| --- | --- |
| Native Full Screen Apps | context style=0, automatic stage creation=0 |
| Native Windowed Apps | context style=2, automatic stage creation=0; Calculator and Notes together |
| Native Stage Manager | context style=2, automatic stage creation=1; Calculator and Notes in one group |
| Stage sidebar left/right | rendered strip and edge activation verified after changing the preference |
| App switcher mirror off/on | opposite partial-card direction verified without restarting SpringBoard |
| Master switch off | flexible-windowing availability=0, scene multitasking support=0 |
| Rootless / RootHide package | sequential builds passed; payload paths, arm64+arm64e slices, plist parsing and fixture exclusion passed |

Evidence and package inspection output are local ignored files under
`packages/research/ios26.1/` and `packages/release/ios26.1-test1/`.
RootHide was built and inspected, not installed on this Rootless VM.
Older iOS versions have source isolation and build checks, not a new physical
device regression run. Physical iOS 26 hardware, external displays and long
running use remain unverified.

The crash directory contains a SpringBoard report from 21:53 during an earlier
iteration (`FBSMutableSceneSettings addPropagatedProperty:`, native remote scene
hosting). Its TrollPadSB UUID differs from the final test package, built at
22:34. No newer SpringBoard report or Preferences report was found at the final
check. This does not establish the cause of the earlier assertion or prove
long-term stability.
Later cold-start Dock crashes were isolated to the VM's legacy
MilkyWay3SubModule SpringBoard injection; see the follow-up above.

## Open iOS 17 issue

The user reports that the Stage Manager recent-app strip and Dock can be shown,
but dragging an app out of either has never worked, including before this test
package. This is a pre-existing reported limitation, not a confirmed iOS 26
port regression. Drag initiation and grouping on the affected iOS 17 device
still require runtime investigation; the iOS 26 VM result does not validate
that path. No speculative drag hooks have been added for older versions.
The user confirmed that **Add Another Window** successfully creates the group.
Targeted 17.3.1 native drag paths and the remaining runtime checks are recorded
in [IOS17-DRAG.md](IOS17-DRAG.md).

## Separate vphone input fixture

`tools/vphone/EdgeInput.m` compensates for synthesized touches without native
HID edge flags by holding the system's edge-input assertion. It runs only on a
`VRESEARCH` kernel, has no Substrate hooks, and is not referenced by the project
Makefile. Neither package includes it. This fixture is unnecessary on a phone.

Build on the Mac:

```sh
xcrun --sdk iphoneos clang -arch arm64e -miphoneos-version-min=15.0 \
  -fobjc-arc -dynamiclib -framework Foundation -framework UIKit \
  tools/vphone/EdgeInput.m -o TrollPadExVPhoneInput.dylib
ldid -S TrollPadExVPhoneInput.dylib
```

On this VM, install the dylib and `EdgeInput.plist` as
`/var/jb/usr/lib/TweakInject/TrollPadExVPhoneInput.dylib` and
`/var/jb/usr/lib/TweakInject/TrollPadExVPhoneInput.plist`, then restart SpringBoard.
To remove the fixture, remove those two files and restart SpringBoard.
The temporary runtime diagnostic fixture is removed after validation.

## Build test packages

Run sequentially because both schemes share `.theos` staging. Save the Rootless
artifact before cleaning for RootHide.

```sh
make clean package THEOS=/Users/hades/theos THEOS_PACKAGE_SCHEME=rootless \
  FINALPACKAGE=1 PACKAGE_VERSION=2.0.1+ios26.1-test1
make clean package THEOS=/Users/hades/theos-roothide THEOS_PACKAGE_SCHEME=roothide \
  FINALPACKAGE=1 PACKAGE_VERSION=2.0.1+ios26.1-test1
```
