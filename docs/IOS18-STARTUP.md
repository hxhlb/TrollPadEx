# iOS 18 startup fix — 2.0.8

The 2.0.7 iOS 18.5 Rootless regression occurred during SpringBoard startup when
SetupAssistant called CFPreferencesSetAppValue. A temporary diagnostic candidate
captured SIGSEGV before forwarding to the existing Safe Mode handler. Both tweak
constructors had completed; the switcher creation entry had not run.

The fault PC was the tweak's CFPreferencesSetAppValue replacement address plus
0x80000000. Matching 22F76 firmware and the candidate's arm64e symbols identified
the caller and replacement. This demonstrates a misdirected function detour on
this setup, without establishing the underlying hook-engine defect.

The fix separates the two CF writer detours from the NSUserDefaults hooks and
installs the CF detours only on iOS 16/17. iOS 18 retains the explicit settings
transaction, NSUserDefaults writers and preference observer/reconciliation.
The existing iOS 16/17/18 Stage/switcher policy and startup latch remain intact.
Raw CF callbacks are no longer synchronously intercepted on iOS 18.

The user accepted Rootless 2.0.7+ios18-startup-test2 on iPhone12,3 / 18.5 / 22F76:
normal startup, normal iPhone switcher, and selecting Stage in system Settings
automatically enabling iPad App Switcher. An authorized Respring applied the iPad
choice and started without Safe Mode or a new diagnostic signal; the user then
reported testing without problems. Host tests cover version and policy guards;
RootHide and other systems have no equivalent new device acceptance.

2.0.8 contains no temporary startup logger, signal handler, crash artifacts or
diagnostic Settings. That code and evidence remain on the local development
branch `iya/ios18-switcher-startup` and are not merged or pushed.
The formal source also updates the expired Discord community invitation.
