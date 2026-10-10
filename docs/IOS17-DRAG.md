# iOS 17.3.1 Stage Manager drag investigation

## Report and scope

The user reports that the recent-app strip and Dock appear normally, but apps
cannot be dragged out of either. The behavior predates the iOS 26 test package.
The user subsequently confirmed that the window menu's **Add Another Window**
action successfully groups another app. Group creation is therefore usable;
the unresolved symptom is drag initiation. The affected phone is unavailable
for runtime tracing.

Static source: local `iPhone14,3_17.3.1_21D61_Restore.ipsw` and its previously
extracted arm64e shared cache. Targeted analysis reuses SpringBoard and UIKitCore
images and extracts only SpringBoardHome and SpringBoardFoundation. No complete
cache disassembly, device installation, or production drag hooks were needed.

## Verified native paths

| Image / method | Address | Observed behavior |
| --- | --- | --- |
| SpringBoard: `SBFluidSwitcherItemContainer initWithFrame:appLayout:delegate:active:windowScene:` | `0x1d362a794` | Creates a `UIDragInteraction` with the item container as delegate and adds it to the container. |
| SpringBoard: layout block in `_layoutAppLayout:roleMask:completion:` | `0x1d3451328` | Obtains `isLayoutRoleDraggable:inAppLayout:` from the modifier and passes it to `setDraggable:` at `0x1d34527b4`. |
| SpringBoard: `SBFluidSwitcherItemContainer dragInteraction:itemsForBeginningSession:` | `0x1d362c2d8` | Returns no drag items if `_draggable` is false or the kill scroll view is decelerating. Otherwise constructs an app drag item with bundle and scene identity. |
| SpringBoardHome: `SBIconView dragInteraction:itemsForBeginningSession:` | `0x1d2d5bca8` | Returns an empty array when `canBeginDrags` rejects initiation. Otherwise returns `dragItems`. |
| SpringBoardHome: `SBIconView canBeginDrags` | `0x1d2d5a6a0` | Consults the resolved drag delegate's `iconViewCanBeginDrags:` when implemented. |
| SpringBoardHome: `SBHIconManager iconDragManager:canBeginIconDragForIconView:` | `0x1d2de0150` | Checks the manager delegate's global/per-icon permission and `reasonToDisallowInteractionOnIconView:`. |
| SpringBoard: `SBIconController iconManager:canBeginDragForIconView:` | `0x1d34bc0a4` | Rejects while the transient overlay presentation manager has an active presentation. |
| UIKitCore: `UIDragInteraction isEnabled` | `0x18a0e3350` | Honors explicitly set enabled state; otherwise checks the class default and the delegate override. |
| UIKitCore: `UIDragInteraction _createDefaultInitiationDrivers` | `0x18a0e37b8` | Selects the default driver provider through the current device idiom registry. |

These are distinct checks. The item container's `_draggable` value is a modifier
decision, not proof that all Stage Manager cards should be forced draggable.
Dock icon delegates also have valid reasons to reject dragging. Static methods
show the paths but do not reveal their values on the affected phone.

## Changes deliberately excluded

- Do not force all `UIDragInteraction` objects enabled or globally spoof the
  iPad idiom. That would affect unrelated Home Screen and system interactions.
- Do not force every icon delegate or switcher modifier to allow dragging.
- Do not treat `SBFIsChamoisWindowDragInteractionAvailable` as the general app
  dragging switch: in the inspected Chamois recognizer setup its conditional
  branch adds a host recognizer for failure relationships after the main
  recognizers have already been installed.
- Do not copy the VRESEARCH edge-input assertion to the phone. The reported
  problem occurs after the strip/Dock can already be revealed.

No production code or test package was changed for this report. The existing
iOS 26 test artifacts retain their previous hashes.

## Remaining runtime proof

On the affected phone, distinguish interaction disabled / missing drivers,
delegate not invoked, delegate returning no items, and later lift cancellation.
Capture the sidebar container's `_draggable`/deceleration state and the Dock
icon's resolved drag delegate/rejection reason before selecting a narrow hook.
Then verify dragging Notes or Calculator into the current group, dismissing
menus, normal Home Screen rearranging, Stage Manager disabled, and the master
switch disabled. An IPSW-only result cannot close this runtime boundary.

Local ignored evidence: `packages/research/ios17.3.1/evidence-manifest.json` and
the four `*-drag-disassembly.txt` files in the same directory. Addresses are
specific to build 21D61 and must not be used as runtime patch offsets.
