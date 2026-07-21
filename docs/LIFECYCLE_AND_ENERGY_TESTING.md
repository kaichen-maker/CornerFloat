# Lifecycle, display and energy verification

CornerFloat has two complementary panel-lifecycle test layers. Both operate on
CornerFloat's own windows and do not request additional macOS privacy access.

## Deterministic panel-policy test

```bash
./dist/CornerFloat.app/Contents/MacOS/CornerFloat --self-test
```

This validates production helpers and persisted models without opening a real
window. Coverage includes geometry limits, visible-screen placement, saved web
workspace compatibility, address resolution, navigation safety, and other
controller invariants that must remain deterministic in CI.

## Real AppKit lifecycle and idle-energy diagnostic

Build the app, then run:

```bash
./scripts/build.sh
./scripts/lifecycle-diagnostics.sh
```

The diagnostic creates a temporary real `NSPanel` and exercises the same window
observers used by production. It:

1. verifies `canJoinAllSpaces` and `fullScreenAuxiliary`;
2. moves the panel completely outside all current display frames;
3. posts the real AppKit screen-configuration notification and verifies the
   production rehome code brings the panel back;
4. posts synthetic workspace sleep, wake and active-Space notifications without
   sleeping the Mac;
5. drives real hide, show, minimize, restore, edge-collapse and edge-reveal
   callbacks;
6. hides the panel and samples the real process CPU and RSS during an idle
   window.

The default idle CPU acceptance limit is 8%. It is intentionally generous enough
for shared CI hardware; a normal local run should be substantially lower. The
duration and threshold can be changed without editing the script:

```bash
LIFECYCLE_IDLE_SECONDS=10 IDLE_CPU_LIMIT_PERCENT=5 ./scripts/lifecycle-diagnostics.sh
```

## Hardware acceptance still required

Automation cannot honestly prove the following without changing external
hardware or entering real sleep. Complete these on the release candidate:

- Connect two physical displays, place a panel on the secondary display,
  disconnect it, and verify the panel moves to the remaining display without
  changing size unexpectedly.
- Repeat with one Retina and one non-Retina display and confirm normal resizing
  and text sharpness after moving the panel between them.
- Switch among at least two Spaces and one full-screen app; verify the panel
  remains available and does not steal focus.
- Hide, minimize and edge-collapse a panel, then confirm Activity Monitor CPU
  returns to idle.
- Put the Mac to sleep for at least 30 seconds, wake it, and confirm visible web
  panels remain responsive and on screen.
- Measure a 10-minute idle run on battery using Activity Monitor or Instruments
  Energy Log. Record the Mac model, macOS version, open panel count, average CPU,
  memory and energy impact.

Do not use `caffeinate`, `pmset sleepnow`, or `powermetrics` as part of the safe
test suite. Those actions change system state or require elevated privileges.
