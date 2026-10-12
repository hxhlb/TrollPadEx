# iOS 26 proportional window scaling investigation

**Historical experiment:** test4 replaces the proportional-scaling feature with
native resizing below the minimum. Current code has no forced canvas, content
scale/stretch or outer aspect lock. The setting is now **Allow Smaller Windows**,
with the same stored key and default-off value. See [SWITCHER.md](../SWITCHER.md).

The original Phone-only experiment and test2/test3 integration below are historical. The earlier
`iya/ios26-window-scaling` branch integrates proportional scaling for app
windows, controlled by a new default-off Settings switch. The release branch
and formal 2.0.2 DEBs remain unchanged; the integration is distributed separately
as `2.0.2+scale-test3` for device testing. Test3 adds the Settings entries below;
the scaling implementation is unchanged from test2.

## Integrated iOS 26 switch

- Settings: TrollPadEx → **Scale App Windows**, after Hide resize corners.
  English, Simplified Chinese and Traditional Chinese strings are included.
- Key: `TPScaleAppWindows`, `com.apple.springboard`, default `NO`.
  The row and its footer are removed outside iOS major version 26. The hosting
  hooks also install only on major version 26, after checking method encodings
  and all required hosting classes. Earlier iOS versions retain their old path.
- Both TrollPadEx's master switch and native multitasking must be enabled.
  Windowed Apps and Stage Manager use the same integration; Full Screen Apps
  retain native geometry. No Phone/bundle allowlist or VRESEARCH restriction
  exists in the production feature. Home Screen and App Library items are excluded.
- `TPWindowScaling.m` keeps each application scene's complete, orientation-sized
  screen canvas and fits its existing host uniformly inside the native viewport.
  Weak maps track presentation/layer owners per scene. The resize restriction
  object and grid configuration are private copies, not shared global mutations.
- Free outer window shapes can leave unused space. This does not create an
  independent window manager or guarantee that every app supports every mode.
- Changing the switch refreshes existing scenes without a respring. Disabling
  it or the master switch restores native scene sizing and identity transforms.
  Refresh uses `sceneIfExists`, never the asserting `scene` accessor. The backing
  container's transform is reset before native frame assignment to prevent
  inverse-scaled bounds during mode transitions.

### Integration validation

iOS 26.1 / 23B85 vphone, Rootless. The first integrated build retained
SpringBoard PID 13631 throughout:

| Check | Result |
| --- | --- |
| Default-off cold start | Native Phone viewport/canvas 375 × 486, identity transform |
| Enable through Settings | Phone and Settings immediately switched to complete 430 × 932 canvases |
| Windowed Apps, flags 1/0 | Calculator, Notes and Safari resized; complete canvases remained inside their viewports |
| Calculator touch mapping | Scaled buttons produced `2+2=4`, confirmed by screenshot |
| Notes keyboard/focus | Search received `Scale25`; tapping the native screen keyboard's A key produced `Scale25A`; search cleared afterward |
| Stage Manager, flags 0/1 | Phone, Notes and Filza resized; Phone entered/deleted `25` |
| Real window movement | Safari in Windowed moved +30/+50; Filza in Stage moved +30/+50; canvas/scale retained |
| Home/app cycles | Two Calculator/Notes/Filza cycles preserved geometry and PID |
| Switch disabled through Settings | All tracked clients restored native canvas/bounds and identity transforms |
| Master disabled while scaling selected | Same native recovery; master preference restored afterward |

The final build adds complete method-encoding checks and correct parent-space
coordinates when restoring an attached host. Its enabled SpringBoard cold start
passed at PID 14590. Full Screen Apps, with the scaling preference still enabled,
restored a 430 × 932 viewport/canvas/host with identity transform. Additional final
package checks and device results are saved under the ignored local
`packages/research/ios26.1/generic-test2-*` files.
The final binary also passed Calculator/Notes resizing in Windowed Apps,
Filza movement (-25/+40) in Stage Manager, and live scaling/master disable.
PID 14590 remained unchanged through these checks, with no Safe Mode and no new
SpringBoard crash report (the newest report remains the historical 02:37:01
Phone-fixture assertion described below). The preference was deleted afterward
to restore its default-off state, and native Windowed Apps flags 1/0 restored.

The local test packages are in `packages/release/ios26-window-scaling-test2/`.
Both Rootless and RootHide build successfully for arm64 + arm64e with deployment
target 15.0. Package validation checks all three localizations, the new default,
unchanged existing Settings rows, and exclusion of VM fixtures. The two formal
2.0.2 package hashes remain unchanged. RootHide is build/package validation only.

`tools/vphone/WindowScalingCapture.m` is a separate, read-only VRESEARCH observer
for native scene/host geometry. It is not in either package and is not required
for the feature. The earlier Phone fixture is likewise not packaged.

Discord, physical iOS 26.0.1, older physical systems, rotation, external displays,
and app-specific classic/landscape-only behavior remain unverified. Six app
samples establish general scope and basic lifecycle/input behavior, not universal
compatibility with all installed apps or other tweaks.

## Settings additions in test3

The bottom of TrollPadEx Settings now includes Discord, QQ group number copy,
Banana repository URL copy, and a separate **Respring (Alternative)** button.
The footer reads "If the top Respring fails, use this button." All new labels,
footers and alerts have English, Simplified Chinese and Traditional Chinese
translations. The original top Respring action and existing settings are unchanged.

The alternative uses `posix_spawn` with the jailbreak-resolved `/usr/bin/killall`,
arguments `-9 SpringBoard`, falling back to `/usr/bin/killall` when available.
RootHide resolves its bootstrap with `jbroot`; Rootless uses `ROOT_PATH_NS`.
It waits off the UI thread, prevents duplicate requests while pending, and
displays a localized failure message if the executable cannot run or exits
unsuccessfully. These new entries are available on earlier supported iOS versions
as well; only the proportional-scaling switch remains restricted to iOS 26.

On the Rootless iOS 26.1 VM, tapping the actual bottom button replaced SpringBoard
PID 14879 with 15618 without Safe Mode. Clipboard reads independently verified
QQ `1126594257` and repository `https://iyaway.github.io`. Discord uses the current
Lunora configuration `https://discord.gg/PraZNv2ZE`; invite membership was not
changed. The final footer was fully visible in the native narrow Settings window.

Latest packages and validation records: `packages/release/ios26-settings-test3/`.
Both schemes build for arm64 + arm64e / minimum iOS 15.0. Package inspection
verifies all new actions/localizations, preserved existing rows, and absence of
VM fixtures. RootHide and older physical devices remain untested at runtime.

## Historical Phone experiment

## Native-window experiments

1. The release tweak allows the Phone window to become shorter, but its native
   resize calculator reports a minimum of 375 x 486 points. The scene handle's
   reported application minimum is zero in this test; the observed floor must
   not be attributed solely to an application-declared minimum.
2. Overriding the calculator's minimum alone does not remove the resize-grid
   limit. An isolated copy of the Phone window's grid configuration, using
   220 x 300 point minima, allows a visibly narrower window (approximately
   234 x 333 points in the captured test). Other display items retain their
   original configuration. SpringBoard PID 4840 remains unchanged during
   resizing and changing the Phone tab, with no Safe Mode flag.
3. This changes the app's layout area rather than scaling its complete image.
   Calls can be displayed, but the keypad is clipped in the short window.
   The keypad also clips at the original short-window height; shrinking its
   layout further does not solve this existing adaptation problem.
4. Returning a larger canvas through
   `SBWindowingSwitcherPersonality preferredSceneSizeThatFits:displayItem:`
   expands the native window in this experiment. It does not provide the
   intended smaller, proportionally scaled presentation.

Experimental sources and raw results are ignored local files under
`packages/research/ios26.1/`: `scaling-experiment.m`,
`scaling-runtime-methods.json`, `scaling-baseline-events.json`,
`scaling-grid-events.json`, `scaling-canvas-events.json`,
`scaling-canvas-views.json`, and `scaling-phone-*.jpg`.
The fixture is VRESEARCH-only and restricted to `com.apple.mobilephone`.
Its injection files and temporary preference are removed after testing.

## MilkyWayReborn reference

Reference repository: <https://github.com/34306/MilkyWayReborn>.
Inspected revision: `aa4d85ed446fa17c07d60f107b109e6f86da2e5f`.

- `MWSceneHelper.m` creates a `_UISceneLayerHostContainerView` for the existing
  app scene. The iOS 26 initializer is `initWithScene:debugDescription:`.
- `MWWindowView.m`, `layoutSubviews`, applies a transform to its hosted content
  in one mode; another mode updates the scene frame to the window's layout
  dimensions. These are separate behaviors.
- The transformed path calculates horizontal and vertical scale factors
  separately. It is not a guarantee of uniform aspect-preserving scaling for
  every arbitrary window shape. A uniform-scale implementation would use the
  same factor on both axes and define how any remaining space is handled.
- `MWPassthroughWindow.m` lets touches outside hosted views pass through. The
  inspected window code does not manually synthesize per-app touch coordinates;
  interactive correctness depends on UIKit and the scene-hosting machinery and
  still needs runtime validation for a new integration.
- These views live in a separate overlay window. This source does not establish
  that assigning the same transform to a native Stage Manager window preserves
  its resizing, focus, keyboard, sidebar and scene lifecycle behavior.

The useful mechanism is retaining a complete app canvas while transforming its
hosted presentation. No full MilkyWayReborn package was installed, and its
backgrounding hooks were not copied into TrollPadEx.

## Native-host prototype

`tools/vphone/archive/PhoneHostScaling.m` is a standalone diagnostic fixture, not a
production tweak source. It runs only in SpringBoard on an iOS 26-or-later
VRESEARCH VM, targets only `com.apple.mobilephone`, and is disabled unless the
temporary `TPTrollPadExPhoneHostScaling` preference is enabled while native
multitasking is active. It preserves the ordinary window type and the system's
window/group management.

The prototype retains a 430 x 932 point Phone canvas in scene settings on this
portrait VM. It copies the Phone item's resize-grid configuration instead of
changing the shared configuration. Its hosting scale uses the same factor on
both axes, fitting the complete canvas inside the native window's viewport.
Free window shapes can leave unused space; this is not an enforced aspect ratio
for the outer native window.

Earlier native-host iterations established:

- Hooking the base `SBSceneView` layout is too early for Stage Manager;
  `SBDeviceApplicationSceneView` subsequently overwrites hosting geometry.
- Hooking the device subclass after its native layout permits complete Phone
  rendering and correct scaled keypad input in both Windowed Apps and Stage
  Manager. Captured native contexts have base style 2, with automatic stage
  creation respectively false and true.
- On that iteration, both modes successfully entered and deleted `25`, and two
  Home / Calculator / Home / Phone cycles per mode preserved SpringBoard PID
  5854 without Safe Mode. Evidence: local `host-leaf-*.json` files.
- Position-only updates subsequently reset the actual scene layer geometry
  without changing the proxy view's recorded scale. Maintaining only that
  proxy transform is therefore insufficient for moving a window.

A later geometry-maintenance iteration exposed an initialization assertion:
`hostLayout` called `SBSceneHandle.scene` before a scene existed. The report is
saved locally as `host-geometry-crash.ips` (02:37:01). The experiment was removed
and the VM recovered. The following iteration used the nullable `sceneIfExists`
getter and passed a disabled cold start and first Phone launch at PID 6414.
The current code avoids that scene-handle lookup entirely: it associates the
existing presentation view with its owner. System assertions are not caught
or suppressed.

The current iteration uses weak maps from the existing presentation view to
its owning device scene view. It fetches that view's actual `hostContainerView`
and applies scale after device layout and
`_UIScenePresentationView._updateFrameAndTransform`. Host attachment is also
handled. It no longer intercepts host initialization or guesses ownership by
scene identifier.

UIKit can manage a detached backing layer whose UIView wrapper has no ordinary
superview/window. Its local frame is projected relative to the owner viewport
for diagnostics, with the detached state recorded. Screenshot/OCR and entering
and deleting `25` independently check display and touch mapping.

The system settings page uses these exclusive combinations:

| Mode | SBMedusaMultitaskingEnabled | SBChamoisWindowingEnabled |
| --- | --- | --- |
| Full Screen Apps | 0 | 0 |
| Windowed Apps | 1 | 0 |
| Stage Manager | 0 | 1 |

Earlier traces used Medusa=1 together with Chamois=1. They exercised automatic
stage creation but did not expose that the initial experimental gate checked
only Medusa. The gate now accepts Medusa OR Chamois. Final tests record both
actual preference values and the live context, using the combinations above.

Native drag attempts from the screen's top edge did not move the window in
either the enabled or disabled experiment. Those attempts are not counted as
successful movement regression. Physical devices, Discord, rotation, external
displays, text-keyboard hosting and complete real-gesture movement coverage
remain unverified; successful Phone input is not proof for those paths.

The full-screen fallback additionally exposed inverse-scaled bounds when native
code assigned a new frame while the experimental transform was still active.
The marked Phone container's frame setter now restores identity before native
frame assignment. Reapplying the experimental scale is deferred until native
presentation updates finish, and only occurs in a target multitasking mode.
Its runtime results are included alongside the positive scaling tests below.

## Final bounded validation

Final frame-restoration iteration: SpringBoard PID 8926, no Safe Mode during
the following checks. Sources compile with `-Wall -Wextra` (excluding unused
notification parameters) without warnings.

| Check | Result |
| --- | --- |
| Windowed Apps, native flags 1/0 | Complete 430 x 932 canvas rendered at approximately 193 x 418 points; `25` entered and deleted correctly |
| Stage Manager, native flags 0/1 | Complete canvas rendered at approximately 188 x 408 points; `25` entered and deleted correctly |
| Home / Calculator / Home / Phone | Two cycles per real mode retained the canvas and SpringBoard PID |
| Full Screen Apps, flags 0/0, test preference still enabled | Native 430 x 932 viewport, layer and canvas restored; no inverse-scaled bounds |
| Test preference disabled, Windowed Apps restored | Original 375 x 486 viewport and canvas restored without a residual scale |

The JSON aggregate is the ignored local
`packages/research/ios26.1/proportional-phone-final-validation.json`; the final
raw checks use the `host-restore-*.json` prefix. The demo image is
`phone-proportional-final-demo.jpg`. These prove the Phone rendering/input
experiment, not a production feature for arbitrary applications. Real movement
coverage remains limited as described above. The experimental injection files
are removed after verification, and the source remains on the isolated branch.
The formal 2.0.2 code and both release DEBs are unchanged.

## Reproduce the isolated fixture

The sources require no additional framework or package dependency. Build with
the iPhone SDK and sign both outputs:

```sh
xcrun --sdk iphoneos clang -arch arm64e -miphoneos-version-min=15.0 \
  -fobjc-arc -dynamiclib -framework Foundation -framework UIKit \
  -framework CoreGraphics tools/vphone/archive/PhoneHostScaling.m \
  -o TrollPadExPhoneHostScaling.dylib
xcrun --sdk iphoneos clang -arch arm64e -miphoneos-version-min=15.0 \
  -fobjc-arc -framework Foundation tools/vphone/archive/PhoneHostScalingControl.m \
  -o PhoneHostScalingControl
ldid -S TrollPadExPhoneHostScaling.dylib
ldid -S PhoneHostScalingControl
```

On the VM, install the dylib and the existing SpringBoard-only
`tools/vphone/EdgeInput.plist` filter as
`/var/jb/usr/lib/TweakInject/TrollPadExPhoneHostScaling.dylib` and
`/var/jb/usr/lib/TweakInject/TrollPadExPhoneHostScaling.plist`, place the control
executable at `/var/tmp/PhoneHostScalingControl`, and restart SpringBoard.

Run `sudo -u mobile /var/tmp/PhoneHostScalingControl enable` and resize Phone.
`capture` writes geometry evidence to
`/var/mobile/Library/Caches/TrollPadEx-scaling-views.json`.
To restore normal sizing, run `disable` and resize Phone again. For full removal,
delete the two fixture injection files and restart SpringBoard. Preserve the
separate edge-input fixture and the VM's legacy-module compatibility profile.
