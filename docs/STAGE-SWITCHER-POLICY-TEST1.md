# Stage/switcher coupling test1

Local RootHide candidate: `2.0.6-2~stage-policy-test1`.
Base: 2.0.5 plus the accepted native-phone entry experiment (`7e24095`).
The mixed Stage-root test2 remains in the previous worktree and is not included.

Only iOS 16, 17 and 18 couple settings while TrollPadEx is enabled:

- Stage ON stores iPad App Switcher ON and multitasking enabled before the Stage write.
- iPad App Switcher OFF stores Stage OFF and Split View enabled before the switcher write.
- Split/full-screen mode changes otherwise preserve the independent switcher choice.
- iOS 15 keeps its independent switcher option; iOS 19/26/27 receive no coupling hooks or writes.

The shared preferences bridge covers bool/object defaults and SpringBoard-domain
CF writers. The plugin page wraps its direct write in the same transaction.
Re-entry is suppressed, linked keys synchronize before the primary notification,
and the SpringBoard observer handles startup inconsistencies and external changes.
Stage state is cached for runtime queries. A controller/root change still needs
Respring; Stage is not activated on a startup phone-root stack before that restart.
The existing alert is reused, including after returning from native multitasking
settings. A footer is shown only on 16/17/18 in the existing three localizations.
A delayed Stage-side restart cannot re-enable Stage after the user disables iPad Switcher.

Host tests cover the actual policy and CF writer callbacks with isolated stores,
version/master/boot/re-entry guards, domain filtering, independent Split/phone
choices and native entry scope. RootHide build/payload/localization checks pass;
keyboard code sections match 2.0.5. No diagnostics or test tools are packaged.
These are not real SpringBoard or iOS 15/16/18 runtime acceptance.

Manual check: install and Respring; disable iPad App Switcher, verify Split selected
and Stage OFF, then Respring and check the phone switcher/minimization/Dock.
Enable Stage through system settings or Control Center; verify iPad Switcher ON,
Respring when the choice changes, then check Stage windows, resize and sidebar.
No automatic device install, Respring, branch push, merge or APT publication.
