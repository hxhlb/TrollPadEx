# TrollPadEx

Enhanced iPhone multitasking and Stage Manager controls based on TrollPad.
The tweak enables Apple's native multitasking paths rather than adding a
separate window manager.

## Features

- Stage Manager on iOS 16 and later, with configurable recent-app strip side.
- Native Windowed Apps on iOS 26, alongside Stage Manager and Full Screen Apps.
- Independent **iPad App Switcher**, enabled by default on supported systems.
  Disable it to use iPhone cards while retaining multitasking; respring to apply.
- **Allow Smaller Windows** on iOS 26: resize below the native minimum in Stage
  Manager and Windowed Apps while each app manages its own layout. Default off.
- Floating Dock, recent apps and App Library controls.
- Optional switcher mirroring, grid scaling and iPad app-switching animation.
- iPad keyboard controls, external-display content scale and AirPlay support.
- Alternative respring button plus Discord, QQ group and repository links.
- English, Simplified Chinese and Traditional Chinese Settings resources.

## Choose a multitasking mode

Enable TrollPadEx in Settings. On iOS 16, use the Stage Manager Control Center
module to switch the native multitasking mode. On iOS 17 and later, use the
system **Multitasking & Gestures** page linked from TrollPadEx. iOS 26 also
provides **Windowed Apps** and **Full Screen Apps** modes.

To open another app while keeping existing windows, use the Dock or its App
Library, or the native **Add Another Window** menu action. Available controls,
window-button placement and workspace appearance follow the installed system.

**Allow Smaller Windows** replaces the old forced-scaling experiment; it does
not proportionally shrink or stretch the whole app. Apps may clip content below
sizes their interfaces support. See [the smaller-window behavior](docs/IOS26-SCALING.md).

## Validation and known limits

The combined iOS 26.1 / 23B85 Rootless vphone regression covers phone-card
removal through the last card, Home/relaunch, window resizing and revealing a
Dock covered by a window in Stage Manager and Windowed Apps. Restoring the
original iPad grid also passed. RootHide has build/package checks; older
physical systems, rotation, external displays and other tweak combinations
have not received the same runtime coverage.

On the reported iOS 17.3.1 phone, Dock/recent-strip app dragging is a pre-existing
unresolved limitation; **Add Another Window** works. Landscape safe-area margins
can affect the left/right layout. KillBackground13 can intercept the Dock reveal
query and prevent the in-app Dock from appearing. Disable that tweak and respring
when investigating this conflict. The maintainer accepted iOS 26 support for
release after reviewing the physical-device diagnostic evidence. Physical
background/blur feedback remains outside the VM validation above.

## Development notes

- [Release changes](CHANGELOG.md)
- [iOS 26 native integration](docs/IOS26.md)
- [Independent switcher and crash regression](docs/SWITCHER.md)
- [Floating Dock diagnosis and recovery](docs/IOS26-DOCK.md)
- [iOS 17 drag investigation](docs/IOS17-DRAG.md)

Rootless and RootHide builds share Theos staging and must run sequentially.
VM observers, input fixtures and archived experiments under `tools/vphone/`
are not included in either package.
