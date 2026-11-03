# iOS 17 phone switcher candidate

Later regression: test5/2.0.6 made foreground minimization and Dock icons
transparent. Initial switcher-only acceptance was incomplete. The rejected
minimize-test1 and current scope-test1 follow-up are tracked in
[IOS17-MINIMIZE-REGRESSION.md](IOS17-MINIMIZE-REGRESSION.md); neither is
validated as a complete physical fix. The test5 description below is history.

## Acceptance and 2.0.6 release

On 2026-11-03 the user confirmed that the latest test5 candidate works perfectly
and explicitly requested source submission and APT publication. This is reported
acceptance on the iOS 17.3.1 RootHide phone used in this investigation, including
the delayed-entry preview/blur symptom. It is not independent device acceptance
on other versions or jailbreak schemes, and does not prove the earlier visual
artifact interpretations or an exact cache-expiry interval. The transient
diagnostic probes/recordings remain excluded from release packaging.

Formal version: `2.0.6`. The failed/superseded candidates below are retained as
research history and must not be distributed as the final release.

## Test5: align the ordinary idle Home/Deck subtree

Test4 no longer crashed, but the user clarified that re-entry becomes visually
wrong after an idle interval, independent of the exit method. The two Home
snapshots after swipe/tap exits had the same native routing chain and wallpaper/
blur fields, so the earlier exit-method hypothesis was withdrawn. The later
recording localizes the dark blur primarily to the wallpaper behind the cards,
not a black Photos-app card snapshot. Read-only sampling is retained locally;
its timings are not an animation-performance benchmark.

The native phone root maintains a Deck as its `multitaskingModifier` child and
uses `_SBHomeScreenFloorSwitcherModifier` while Home is active. Its native floor
updater shares that Deck as the switcher floor instead of attaching/removing a
second copy. Test4 still used the iPad Main root's nil multitasking factory and
empty Home routing floor. The native Home floor explicitly requests asynchronous
surface retention (`wantsAsynchronousSurfaceRetentionAssertion = YES`), while
the empty routing chain has no child policy requesting it. This is a specific
standby-policy mismatch consistent with delayed re-entry, not independent
proof of a five-second cache-expiry root cause.

Candidate `2.0.6~switcher-test5` aligns this native pairing only for the iOS 17
Main root with the iPad switcher off. It provides a live owned Deck through the
native multitasking factory, shares it as the ordinary switcher floor, and
selects the native Home floor only for Home mode without floating/Peek state.
Other App/window routes, Stage Manager root classes, non-nil native factory
results, default-on/master-off and other OS versions remain native. The outer
iPad platform/windowing root stays in place.

There is no timer, cache timeout change, permanent snapshot association or
manual forced surface-retention return. Apple's Home floor supplies its own
policy; the native child tree owns and retires its objects. The earlier
completed-floor, cross-root ownership and animation corrections remain.

The expanded host production-callback contract fails against test4's absent
idle Deck subtree and passes the paired Home/Deck identity, live-object reuse,
retired-object replacement, floating/Peek/App fallbacks and OS/default guards.
Native method/ivar signatures were checked against 21D61. Physical delayed
re-entry acceptance remains pending. Test immediately, then after 5–10 seconds
and 20–30 seconds on Home, with both exit methods and several repeated cycles.
No automatic installation, respring or publication is part of this handoff.

Both test5 packaging schemes passed build/payload checks, with Settings
resources unchanged and no probes, tests or recordings included. Their hashes
are stored in the ignored `packages/release/ios17-switcher-test5/validation.json`.
RootHide debug symbols are retained locally; delayed-entry device acceptance
is not yet claimed.

## Test4: native Deck gesture and entry/exit transitions

The user confirmed test3 no longer crashed, then reported abrupt switcher
entry/exit. The supplied six-second recording shows cards appearing at the
screen edge before jumping to their final Deck position, and disappearing
without a matching exit transition. Frame review is diagnostic evidence, not
a benchmark or a statement about other users' frame rates.

In the 21D61 image, the retained iPad `SBMainSwitcherRootSwitcherModifier`
returns nil for the ordinary style-1 main transitions and the type-1 bottom-edge
gesture. The native phone root instead creates `SBHomeGestureRootSwitcherModifier`
with a fresh Deck and its native resign-transition flag, `SBHomeToDeckSwitcherModifier`
for Home/switcher transitions, and `SBDeckToFullScreenSwitcherModifier` for
App/switcher transitions. The phone factory's direction is 1 when entering
the switcher and 0 when leaving it. Relevant initializer/getter signatures and
the Main root's environment-mode ivar encoding were checked in the same image.

Candidate `2.0.6~switcher-test4` supplies those native objects only when the
iOS-17 Main root returns nil, the tweak is enabled and the startup iPad choice
is off. It retains the existing platform/windowing root and test3's floor
lifetime correction. It does not reuse completed transition Decks, synthesize
animation curves, force animation duration, or disable Reduce Motion.
Native non-nil results and unrelated, App Expose, floating, Peek, banner,
Continuity and display-move transitions are preserved. The new animation
hooks require matching native classes, method signatures and ivar layout.

`test_phone_switcher_animations.py` extracts the production callbacks and
installation block, checking native gesture initialization, all four ordinary
Home/App entry/exit routes, IDs, directions, layouts, fresh Deck identity,
original-result identity, special-case fallbacks, master/default behavior and
OS boundaries. It reproduces test3's absent Deck gesture and passes test4 with
host-only native-path fixtures. The existing floor lifecycle regression remains
required. Neither test replaces real SpringBoard animation acceptance.

Manual check: with the iPad switcher off and after respring, enter from Home,
exit to Home, enter from an App and select a card. Repeat several cycles and
dismiss cards. Verify the native iPad grid still returns after enabling the
option and respringing. Physical test4 acceptance is pending; no publication
or automatic phone installation is part of this handoff.

Both test4 packaging schemes passed build/payload checks with the existing
Settings resources unchanged and no test fixtures, probes, or recording media
included. Hashes are recorded in the ignored
`packages/release/ios17-switcher-test4/validation.json`; RootHide debug symbols
are retained locally for matching any subsequent report.

## Test3: do not retain a removed/completed floor

The physical `SpringBoard-2026-11-03-162839.ips` matches test2's RootHide UUID
`6DAA8B7F-F8AE-3C09-ADBA-C70827435A2D`. Its Objective-C exception occurs in
`MethodCacheDispatchDataForSelectorIndex +392`, reached from
`SBFluidSwitcherViewController _updateAnimatableProperties +104`. The matching
21D61 image identifies `animatablePropertyIdentifiers` at that call site and
the native assertion text as `couldn't find implementor for %@`. The nearby
Foundation dictionary symbol is not evidence of a preference-file failure.

Test2 held its replacement Deck in an association after native removal.
The native removal path sets modifier state to 1, disconnects the query chain,
and clears its parent; adding a modifier does not reset its state. The expanded
host lifecycle fixture consequently reproduces test2 returning that retired
object on the second opening. This is a concrete lifetime defect consistent
with the report; physical causality and recovery still need repeat-cycle tests.

Candidate `2.0.6~switcher-test3` removes that association. It reuses only the
current native floor of the expected Deck class when its parent is the same
root and its state is 0. Otherwise it allocates a fresh native Deck. Getter
signatures for floor, parent, and state are checked before installing these
iOS-17-only floor hooks. Native transitions and query algorithms are retained;
there is no assertion suppression or fabricated empty query result.

Production-callback tests now cover repeated enter/remove/re-enter sessions,
active-floor reuse, completed floors still attached, cross-root ownership,
and the earlier original-result/OS/ABI boundaries. They fail the lifecycle case
against test2 (`b96eb06`) and pass test3. These remain fixtures informed by the
native implementation, not execution of SpringBoard's UI.

A separate native-process lifecycle experiment was blocked by the system's
SpringBoardUI framework load restriction before its lifecycle checks executed.
That failed probe is not counted as original-code runtime validation and did
not attach to or execute code inside SpringBoard. No test3 installation or
device respring is part of this handoff; real-device acceptance is pending.

Both test3 packaging schemes passed build/payload checks, including unchanged
Settings resources, arm64/arm64e slices with signature commands, and exclusion
of probes/tests. Their hashes are saved under the ignored
`packages/release/ios17-switcher-test3/validation.json`. Device crash recovery
and repeated real UI transitions have not been performed by this handoff.

## Test2: replace the actual legacy floor

The user reported no visual correction with test1. Read-only task-memory checks
on iOS 17.3.1 matched the installed test1 UUID and confirmed the startup option
was off, the Deck class prepared, and the main-factory hook installed. The
active content controller was already `SBDeckSwitcherViewController`. With the
switcher visible, however, its preserved `SBiPadOSPlatformSwitcherModifier` root
contained `SBMainSwitcherRootSwitcherModifier -> SBMixedGridSwitcherModifier`
and native grid children. Thus the remaining grid was the active floor layout,
not an unread preference or an absent hook.

The matching native `floorModifierForTransitionEvent:` at `0x1d3487d60`
directly allocates/reuses the MixedGrid floor for a regular mode-2 transition;
it does not call the helper modified in test1. `floorModifierForGestureEvent:`
branches directly to that implementation, so both selectors require hooks.
Both method-list entries have `@24@0:8@16` signatures.

Candidate `2.0.6~switcher-test2` adds signature-checked hooks on those two iOS 17
selectors. Only an exact native `SBMixedGridSwitcherModifier` result is replaced
when the tweak is on and the startup iPad choice is off. A per-root associated
native Deck is reused across transition/gesture queries. The system root,
child insertion/removal, window management and native Deck algorithms remain
in place. Specialized App Expose/subclass results, nil, default-on, master-off,
and all other OS versions keep their original floor results.

The expanded production-callback host contract reproduces test1's failure on
the direct transition floor, then passes both fixed entry points, stable Deck
identity, original-call counts, specialized/nil fallbacks, and OS boundaries.
This is still fixture-based callback proof; physical test2 rendering, app
activation, removal and animation acceptance are pending. Transient read-only
probes used for diagnosis are not part of the package.

RootHide and Rootless test2 builds and package-structure checks passed; the
Settings resources remain byte-identical to 2.0.5 and probes are absent.
Test2 hashes are recorded in the ignored
`packages/release/ios17-switcher-test2/validation.json`. No installation or
respring was performed during the locked-device diagnosis. Temporary native
probe executables and their entitlement file were removed from the phone.

## Test1 record (superseded; do not distribute)

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
