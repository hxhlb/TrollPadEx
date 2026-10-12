# iOS 26 smaller windows

The current setting is **Allow Smaller Windows**. It replaces the earlier
**Scale App Windows** proportional-scaling experiment. The stored key remains
`TPScaleAppWindows` in `com.apple.springboard`, with default NO, so existing
preferences do not need migration.

## Behavior

- Available only on iOS major version 26.
- Works in native Stage Manager and Windowed Apps while TrollPadEx is enabled.
- Lowers the native app-window resize minimum and its associated grid limits.
- Keeps native scene sizing, hosting, input and app layout. It does not force a
  larger canvas, stretch content, apply a scale transform or lock the outer ratio.
- Apps lay out their own interfaces. Controls may clip when an app does not
  adapt to a very small window; a lower safety floor still applies.
- Turning the option off restores native minimum sizing on subsequent resize
  calculations. Full Screen Apps and earlier systems keep their native paths.
- Home Screen and App Library display items are excluded. Per-item restriction
  objects and grid configuration are private copies; shared defaults stay intact.

## Implementation and validation

`TPWindowScaling.m` installs three signature-checked native resize hooks. The
public function/file names and stored preference key retain their original
names for compatibility; the shipped behavior is native smaller-window layout.
English, Simplified Chinese and Traditional Chinese Settings strings are kept.

The latest combined regression and iPhone-switcher integration are documented
in [SWITCHER.md](SWITCHER.md). Dock-specific checks and limitations are in
[IOS26-DOCK.md](IOS26-DOCK.md). RootHide package checks do not constitute
RootHide device testing, and older physical devices have not been rerun.

## Archived experiment

The proportional-hosting investigation, MilkyWayReborn comparison and Phone-only
VM fixture are preserved in [the research archive](research/IOS26-PROPORTIONAL-SCALING.md)
and `tools/vphone/archive/`. They are excluded from the production Makefile and
packages and are not instructions for the current setting.
