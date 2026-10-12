# Independent switcher and native smaller windows

Branch: `iya/ios26-window-scaling`. Candidate: `2.0.2+scale-test14`.
Formal 2.0.2 artifacts remain unchanged; nothing is published.

## Settings contracts

- **iPad App Switcher** / `TPUseiPadAppSwitcher`, SpringBoard domain:
  default YES, including when the key is absent. The setting is shown on all
  supported systems. NO selects native iPhone Deck cards. The applied choice
  is latched at SpringBoard startup; changing it requires a respring. This avoids
  rebuilding controllers/gesture managers in the middle of a session. Grid
  scaling, mirroring and iPad animation controls are disabled in Settings when
  the desired iPad choice is off; their stored values are retained.
- **Allow Smaller Windows** retains the test2/test3 `TPScaleAppWindows` key and
  default NO. It replaces proportional scaling with native app layout below the
  system minimum. This setting and its hooks remain confined to iOS major
  version 26. There are no forced full-screen canvases, host transforms,
  stretching or outer aspect locks. Applications may still clip controls at
  sizes they do not adapt to. Disabling it restores native resize constraints
  on subsequent sizing calculations.
- Both controls include English, Simplified Chinese and Traditional Chinese.
  The existing bottom respring/community entries remain in the package.

## Native integration

Style 1 selects `SBDeckSwitcherViewController`; style 2 retains the existing iPad
presentation. Older default-on raw styles defer to their original getter. The
master-off paths defer to native styles and leave the new resize hooks inactive.

Windowing must retain the iPad platform/window-aware root. Changing only the
view-controller class left a grid, while replacing the complete root lost
window resizing. The final factory hook targets
`SBContinuousExposeRootSwitcherModifier multitaskingModifierForEvent:`. It
replaces only the regular Expose presentation, excluding specialized subclasses.
On iOS 26, a small runtime subclass of Apple's `SBRootWindowingModifier` adapts
the native Deck to modern item-frame queries, only when the original factory
returns `SBExposeWindowingModifier`. The regular window root, floor,
strip and app-state handlers remain native. Older legacy Expose presentations
use the Deck directly. Native factory caching is retained across events.

### iOS 26.0.1 legacy presentation correction (test5)

The 23A355 IPSW's factory at `0x21dcc1aa4` still tests
`windowManagementContext.isFlexibleWindowingEnabled`: YES creates
`SBExposeWindowingModifier` (`SBWindowingModifier` family), while NO creates
`SBAppSwitcherContinuousExposeSwitcherModifier` (`SBSwitcherModifier` family).
The 26.1 factory no longer makes this distinction. Test4 wrapped both results
in a modern windowing modifier on all iOS 26 systems, changing the legacy
result's interface family. Test5 returns a plain `SBDeckSwitcherModifier` for
the legacy result, as on older systems, and keeps the adapter for modern results.
The default-on, master-off, specialized subclasses and cached-result paths keep
their previous behavior. No window-management preferences are changed by this fix.

A standalone 26.1 process exercises the production factory source against both
native result classes: test4 fails the legacy family check; test5 passes both
family checks and preserves the original object with the iPad choice on or the
master off. Local evidence: `SwitcherFactoryContract.m` and
`switcher-factory-compatibility.json` under the respective research directories.
This confirms the compatibility defect and correction. At that stage no physical
crash report or 26.0.1 runtime was available; the later report is analyzed below.
Test5 also cold-started on the Rootless 26.1 VM with the iPad switcher off;
three app/switcher cycles in each of Windowed Apps and Stage Manager and a
Calculator resize preserved PID 23980 without Safe Mode or a new crash report.

The Deck has no organic App Expose pile. The adapter represents that optional
concept with a nil getter; native gesture code skips its optional pile filtering
when nil. Existing implementations are preserved. There is no generic exception
or assertion suppression. The non-windowing main-switcher factory also has a
mode-2 Deck path; its `_new` selector keeps its +1 ownership contract using an
explicitly annotated C function type. Private signatures are checked before use.

`TPWindowScaling.m` now only relaxes the minimum calculator and copies per-item
restriction/grid configuration. It no longer hooks scene settings, hosting
layout, presentation transforms or container frame setters. Below iOS 26 these
resize hooks do not install. Window-management keys and capability hooks retain
their previous implementation.

## Validation and boundaries

Runtime device: Rootless vphone, iOS 26.1 / 23B85. RootHide is build/package
validation only. Local ignored evidence uses `switcher-test4-*` and
`smaller-test4-*` prefixes in `packages/research/ios26.1/`.

- Standalone default test verifies missing / NO / YES as YES / NO / YES. Its
  executable defaults domain is separate from SpringBoard's domain.
- iPhone cards scroll horizontally and activate an app in Windowed Apps.
- Windowed Apps (1/0): Notes and Clock simultaneously show independent windows;
  Clock resizes and moves. Switching to Stage Manager (0/1) preserves both
  windows, with native strip model/layout modifiers in the active query chain.
- Notes and Settings shrink below the original width and grow back. Their
  canvas tracks the window and host scale remains 1. Full Screen Apps (0/0)
  restore 430 x 932 viewport/canvas/host on this VM, with identity scale.
- iPhone cards remain available in Stage Manager and Full Screen Apps.
- After the startup-latch fix, a real respring restored the missing-key default
  to `SBGridSwitcherViewController`, raw/effective style 2, at PID 22475 with no
  Safe Mode. Saving NO without respring left that running controller/style
  unchanged. The desired key was deleted again, and native minimum sizing
  clamped Calculator to at least 375 x 486. See `switcher-test4-default-result.json`.
- iOS 17.3.1 static symbols confirm the raw/effective style getters and the
  continuous-expose factory entry. This is not physical-device runtime proof.

Discarded experiments include a legacy phone-root gesture-completion crash at
17:22:07 (missing `organicExposeAppLayout`), ineffective row-only changes, and a
whole-root replacement that lost resizing. A VM-only direct factory-refresh
shortcut also asserted on duplicate system-gesture registration at 19:22:36;
that shortcut was removed. The production setting uses a startup-latched choice
and requires a respring instead. Reports are retained locally as
`switcher-phone-root-crash.ips` and `switcher-refresh-crash.ips`.

The earlier optional Notes keyboard probe did not obtain its expected OCR text
after focus/input and is not counted as passing keyboard regression. The prior
test3 keyboard result does not validate the new smaller-window behavior.

The package excludes all VM observers, tests and older Phone fixtures. Both
architectures/schemes retain the existing deployment target and layouts. Older
physical systems, physical iOS 26.0.1, rotation, external displays and other tweak
combinations remain unverified. The combined test6 Dock gesture recovery and
its validation limits are described in `IOS26-DOCK.md`; the background/blur
feedback remains unresolved. The
two-date issue belongs to Lunora, and system window-button position/colors are
not changed.

## App-removal crash follow-up (test14)

The physical 26.0.1 / 23A355 report `SpringBoard-2026-10-11-161315.ips`
aborts in the legacy query dispatcher at
`_SBHomeScreenFloorSwitcherModifier.transactionCompletionOptions +24`.
The matching IPSW instruction is the `appLayouts` query, not an animation flag.
Clean 26.1 VM failures also identified missing scroll-offset, container-bounds
and layout-direction queries during temporary removal/Home transitions.

On iOS 26, the private Deck subclass supplies the 15 content-view data queries
used by native Deck layout/interaction methods. Each signature is checked;
object, BOOL, CGFloat, NSInteger, CGRect and CGPoint returns/arguments use typed
calls. Actual layouts, geometry, settings, direction and policy come from the
owning native switcher view. Apple's Deck layout algorithms remain intact.
The Home-floor's layout/motion queries use this provider only when its query
chain contains the phone Deck. Other presentations defer to their originals.
Earlier systems retain the original Deck class and native transition paths.

A second defect affected the modern adapter's lifetime/query tree. Native
`SBChainableModifier.copyWithZone:` performs class allocation/initialization;
copying this root adapter produced an empty modifier and dropped its contained
Deck. A VM-only trace confirmed that the inner legacy Grid transition therefore
received the entire modern adapter and froze during temporary-child cleanup.
Only the inner Grid's getter unwraps this tweak's adapter to its associated
Deck; the outer transition retains the modern adapter. Native modifier copying
originally dropped that association and its entire child query chain. The
adapter now implements a +1 `copyWithZone:` that copies the Deck and rebuilds
its native root through `initWithSwitcherModifier:`, attaching the association
to every copy. The native root's cached `switcherModifier` getter is not used
as a substitute for that ownership. System classes, initializers and transitions
are not replaced; native adapters, other modifier types and default-on/master-off
paths retain their original behavior. No assertions/exceptions are suppressed,
and animation preferences are not forced off.

`DeckContextContract.m` exercises the production code against native 26.1
classes, a content-view fixture and native `SBAppSwitcherSettings`. It verifies
0/1/3-page visibility, content size, reduced-motion completion options,
default-on/master-off fallback, copied adapter/Deck identity, the original Grid
class and a complete nested native Home transition with empty visibility.
The old copy produced an empty query chain; test14 preserves the Deck and
native defaults. Evidence: `switcher-test12-copy-chain.txt` and
`switcher-test14-query-contract.txt` under the local research directory.

With a temporary read-only observer, test14 cleared every visible card in Stage
Manager and Windowed Apps, returned Home and relaunched Calculator, retaining
PID 29423 without Safe Mode. The trace confirms Deck inputs and paired
transaction completion. The observer is not packaged and was removed for a
separate cold-start regression. Without observers, PID 29598 passed confirmed
card removal to empty, Home and relaunch in both modes. The native accessibility
owner can become DockFolderViewService when no cards remain; its Dock buttons
are excluded from card matching. Before/empty screenshots accompany the actual
card-element results. The removed observer's trace stayed byte-for-byte unchanged.
Three Notes resizes and both modes' covered-Dock/reveal checks also retained
PID 29598, with `SBChamoisHideDock` still absent. Evidence:
`switcher-test14-clean-summary.json`, `switcher-test14-clean-fixture-proof.json`,
`dock-test14-*-result.json` and their corresponding screenshots. Failed internal candidates 6-13 are
superseded and must not be distributed. RootHide and physical 26.0.1 still require device
validation; package checks do not replace those tests.

Final recovery restored the prior `TPUseiPadAppSwitcher=1` and Windowed Apps
preferences, then cold-started PID 29901. Calculator/Notes opened normally;
the original iPad grid displayed 146 x 297-point cards and exited/relaunched
Notes without a PID change or Safe Mode. Evidence:
`switcher-test14-restored-on-result.json` and `switcher-test14-default-on-ui-result.json`.

## Subsequent tester feedback

The user relayed that respring works and Safe Mode no longer occurs. This is
reported device feedback after the test14 handoff; the exact installed artifact
and reproduction path were not independently recaptured. The switcher/Dock VM
results above remain the reproducible validation record.

The subsequent Dock report remains unresolved: Floating Dock is enabled, but
neither Stage Manager nor Windowed Apps reveals it inside apps, even when the
window is centered. This is broader than the covered-window gesture case passed
on the VM. See `IOS26-DOCK.md` for the bounded native comparison.
