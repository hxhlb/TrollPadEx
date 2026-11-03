# iOS 17 foreground App minimization follow-up

After accepting switcher behavior in test5/2.0.6, the user reported foreground
Apps becoming transparent during minimization and Dock icons remaining hidden.
They confirmed this also happens with the independent animation tweak disabled.
This investigation treats it as a TrollPadEx regression, not an established
third-party conflict. That other tweak's source and settings are not modified.

The last Home/Deck change selected `_SBHomeScreenFloorSwitcherModifier` for any
ordinary transition targeting Home, including an unfinished App (mode 3) to
Home (mode 1) transition. The 21D61 native Home floor returns opacity 0 for App
content. Switching to this terminal floor while foreground minimization is
still running is a concrete scope error consistent with premature disappearance;
Dock icon recovery and sole physical causality remain to be verified.

The matching `SBTransitionSwitcherModifier handleTransitionEvent:` dispatches
phase 1 to `transitionWillBegin`, phase 2 to `transitionWillUpdate`, and phase 3
to `transitionDidEnd`. The event phase getter is `Q16@0:8`.

Candidate `2.0.7~minimize-test1` preserves the original proposed floor for the
App-to-Home route until phase 3. It restores the phone Home policy at completion,
including gesture-floor queries after the root mode has already become Home.
A per-root pending flag follows the native App-return phases; nested Home
updates do not clear it prematurely. It retains no App, layout or preview
object. Completion/cancellation and switcher-return paths clear the flag.
The candidate retains 2.0.6's Home/Deck pairing and switcher transitions. There is no timer,
global alpha override, third-party modification or APT publication in this test.

The expanded production-callback host contract fails this unfinished-App-return
case against 2.0.6 (`aff5891`) and passes the candidate for phases 0/1/2, completion,
and switcher-to-Home behavior. Existing lifecycle and OS/default guards pass.
These are fixture-based callback checks, not SpringBoard UI acceptance.

Manual check: minimize several foreground Apps by gesture and check Dock icons
after returning Home; cancel a partially completed gesture; then recheck ordinary
switcher entry/exit and delayed re-entry. Test the independent animation option
off first, then on, to verify both baseline recovery and coexistence. Physical
acceptance is pending; no automatic phone installation or respring is performed.

Both candidate schemes passed build/payload checks, with the existing Settings
resources unchanged and no probes, tests or media packaged. Hashes are stored
in the ignored `packages/release/ios17-minimize-test1/validation.json`, and the
RootHide symbols are archived locally. The public 2.0.6 artifact is not replaced
by this test handoff.
