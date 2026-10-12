> Historical test15/test16 diagnostics. Removed from formal 2.0.3 at the maintainer's request; no diagnostic controls or sampler ship in the release. Source remains in Git history.

# Opt-in iOS 26 Dock diagnostics

Settings → TrollPadEx → **Dock Diagnostics**. The setting is hidden outside
iOS major version 26 and defaults to off. Enabling takes effect without a
respring. Leave it enabled across a respring when capturing initial Dock state.

## Tester procedure

1. Install the diagnostic candidate and respring.
2. Enable **Enable Dock Diagnostics**. Respring once more for a startup capture.
3. Open an app, try to reveal the Dock several times, then repeat in the other
   window mode. Keep the test within 10 minutes; note which mode and switcher
   setting were used. Window dragging/resizing can be included in the test.
4. Return to TrollPadEx Settings, disable diagnostics, and tap
   **Export Dock Diagnostics**. Save `TrollPadEx-Dock.log` to Files, then attach it
   to the message for the maintainer.
   Exporting does not send anything automatically.

After 10 minutes sampling stops. Toggle off/on to start another session.
The latest current/previous files survive a respring and remain available after
disabling logging. The two rotating files total at most 1 MiB. The export is a
separate temporary copy, so later log writes do not modify the shared report.
If Settings cannot export, the source files are available through Filza:

```
/var/mobile/Library/Logs/TrollPadEx-Dock.log
/var/mobile/Library/Logs/TrollPadEx-Dock.log.previous
```

## Evidence and interpretation

The JSONL report records system version/build, observer signatures, timestamps,
SpringBoard PID, actual/desired switcher choice, multitasking and Dock settings,
FrontBoard property registration, existing controller/remote-content state,
active assertion level, native/effective gesture results, keyboard/switcher
visibility and native gesture-entry counts. It records no app identifiers,
window titles, screenshots, touch coordinates or app content.

Format 2 additionally compares the content controller's Dock/scene lookup with
the main scene's existing controller and its data-source scene resolver. Method
implementation image basenames help identify an intercepted lookup. The
observer's own content-gesture hook normally appears as `TrollPadSB.dylib`;
`observerHooks` records the implementation image before this observer installs.
An image name alone does not prove that native instructions are unmodified or
that a particular tweak caused the failure.

`dock_not_created` / `dock_not_created_support_denied` distinguish a missing
controller from `remote_not_created` / `remote_content_not_ready`.
`assertion_denies_gesture`, `controller_denies_gesture` and
`content_denies_gesture` identify sampled permission gates. `dock_presented`,
keyboard/lock/switcher states can explain normal denials. Unsupported getters
produce JSON null; unavailable observers are listed rather than treated as
false results. A ready/allowed snapshot with no Dock-gesture entry narrows the
next investigation, but does not prove that a correct reveal gesture was made.

Diagnostics preserve every hooked native result. They never create or present
a Dock, modify assertions, set auto-hide preferences or alter scene settings.
Sampling runs on the main thread; file writing uses a serial background queue.
Default-off does not install observer hooks, create a timer or write a log.
Observers remain inert after a live disable until the next respring.

The standalone `tools/tests/DockDiagnosticsContract.m` checks unknown versus
false, missing/unready/denied/allowed and already-presented classifications,
disabled no-op, bounded rotation and complete JSONL records. It is not packaged.
