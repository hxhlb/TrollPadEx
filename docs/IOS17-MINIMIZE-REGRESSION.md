# iOS 17 foreground App minimization follow-up

Historical investigation: superseded by the 2.0.7 native-entry/coupling policy.
See [RELEASE-2.0.7.md](RELEASE-2.0.7.md) for the current release boundary.

## Current status: scope-test1, physical acceptance pending

The user rejected `2.0.7~minimize-test1`: foreground minimization recovered, but
idle switcher entry became wrong again. Its phase guard is superseded; the
historical explanation below is not a claim of combined success.

`2.0.7~switcher-scope-test1` removes the Home-floor substitution and permanent
Deck child completely. Native Home/App routing retains its identity throughout
all transition phases. Foreground App gestures are delegated to the original
factory; only Home/Deck gestures and the four explicit switcher entry/exit
transitions get phone switcher drivers. The live-owned Deck floor correction
and completed-object lifetime safeguards remain. iOS 26 code paths are unchanged.

The only replacement for the earlier Home-floor cache policy is the native
coordinator's `switcherContentController:setCacheAsynchronousRenderingSurfaces:`
request. A false request becomes true only for the exact Deck content controller
currently owned by the embedded display, while its real switcher controller is
in Home mode, TrollPadEx is enabled, and the startup iPad switcher choice is off.
Other requests keep their value, and the original delegate is called once.
There is no App/Dock alpha, frame or animation-duration override.

21D61 native evidence (arm64e image UUID
`7346EBA7-83F7-30E7-9D81-18C47EA290EF`):

- `_updateAsynchronousSurfaceRetentionAssertion`, `0x1d3467f0c`, reads the root
  query and forwards its Boolean to that coordinator delegate.
- Coordinator setter `0x1d373c888`, ABI `v28@0:8@16B24`, maintains a weak request
  set and the native asynchronous surface-cache disable timer. Its native
  `disableAsyncRenderingSurfaceRetention` policy still runs. This candidate
  neither changes that setting nor edits the timer duration.
- Embedded-display identity check `0x1d3748bc8`, ABI `B24@0:8@16`, compares the
  current embedded switcher controller's content by identity.
- Native phone Home floor requests surface retention at `0x1d35396ac`.
  This is evidence for copying a cache policy instead of Home-floor geometry;
  it does not prove the user's visual artifact has this sole cause.

Host contracts first fail against 2.0.6's permanent desktop Deck injection,
then pass native Home/App floor identity across phases 0–3, untouched App
minimize driver, switcher transitions, retired Deck handling and Home-only cache
request guards. OS/default/native-specialized fallbacks are covered. These are
callback fixtures, not SpringBoard animation proof.

Physical acceptance must cover one installed build: minimize Apps and verify
Dock icons, cancel a minimize gesture, enter/leave the switcher from Home and an
App, then repeat after 5–8 seconds and 20–30 seconds on Home. Also check card
dismissal. No automatic device install, respring, push or APT publication.

Both scope-test1 schemes passed compilation and package checks. Settings resources
and all arm64/arm64e `__text` slices for TrollPadUI and the preferences bundle
match 2.0.6. No probes, tests, diagnostics or media are packaged. The package
manifest and matching scheme-specific symbols remain in ignored local research/
release directories. Signature load commands were checked; this is not a claim
of device-side loader acceptance or independent cryptographic verification.

## Historical minimize-test1 (superseded)

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
