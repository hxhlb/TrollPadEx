# App Library Dock switch test

## Combined beta2 candidate (2026-10-22)

The isolated `iya/keyboard-dock-beta` candidate combines this Dock restriction
with the phone keyboard fix from `b340970`. The original dirty
`fix/dock-library-switch` checkout is preserved. Package version:
`2.0.4~beta2`. Formal publication is paused while the user tests the Dock switch.
The keyboard fix already passed portrait Safari on iOS 17.3.1; the Dock change
still needs OFF/ON checks after respring. No diagnostic probes are packaged.

Local candidate: 2.0.4~beta1. Not published.

The old implementation saved Apple's SBAppLibraryInDockEnabled key but did not observe it in TPPrefsObserver or post the TrollPadEx save notification for that row. Its native Dock policies had no explicit OFF restriction. This is a source gap, not a reproduced physical-device failure in TrollPadEx.

Add observer/default handling (missing YES, explicit NO/YES retained), notification, and ABI-checked native library getter/setter restrictions. When TrollPadEx is enabled and the saved switch is OFF, enabled/visible setter arguments are clamped to NO; native NO remains NO. When the switch is ON or the master is OFF, native requests/results pass through unchanged. The native system still owns rendering and layout; no new polling or forced Dock reconstruction.

Targets: local SBFloatingDockViewController and newer SBFloatingDockRootViewController setters, plus SBFloatingDockController's forwarded status query. iOS26.0.1 static symbols confirm the root enabled setter and iOS26.1 saved metadata confirms the controller BOOL query. Every method's complete argument/return shape is checked at runtime; unavailable methods are skipped.

Keep the existing respring requirement. No phone/VM restart, installation, image capture or APT publication performed. Verify OFF/ON after respring on older local Dock and iOS26 remote Dock, with and without DuoFlow. Native metadata and host contracts are not physical rendering proof.

Host contracts: 2 passed. Both RootHide and Rootless packages passed payload inspection: three arm64/arm64e binaries, minimum iOS15.0, both signatures, native library methods linked, preference notification and entry resources. No APT publication or source push.
