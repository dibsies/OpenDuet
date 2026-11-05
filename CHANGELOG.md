# Changelog

## 0.4.28 beta

- Handle the observed split Volume Down notification: mute arrives first,
  followed about 125 ms later by the lower volume. Wait briefly before
  treating an isolated mute-on event as a standalone Mute key.
- Remove the unsolicited −12 dB output ceilings and their settings. Restore
  the full output range with confirmation for jumps >25 dB and entry to 0 dB.

## 0.4.27 beta

- Restore the requested macOS mute state after level writes, rather than
  relying on a snapshot taken before the write. Treat combined native
  level/mute changes as volume adjustments while preserving explicit mute.
- Add local keyboard-volume event diagnostics for the unresolved live issue.
- Prompt only for a single output increase greater than 25 dB; remove
  repeated prompts for ordinary adjustments. Always confirm entry to full
  output (0 dB), even from −1 dB. Keep configurable ceilings.
- Remove the repeated heading inside the collapsible direct monitor mixer.

## 0.4.26 beta

- Clear macOS automatic floor-mute when a fixed 2 dB Volume Down step
  still leaves Main Out above its minimum; keep the explicit Mute key separate.
- Replace angular dial tracking with relative vertical dragging and Shift
  fine adjustment. Clicking a dial alone never changes its value.
- Guard large output increases from the console, quick mixer, keyboard and
  hardware knob. Add independent configurable output ceilings, initially −12 dB.
- Make Direct monitor mixer collapsible and remember its expanded state.

## 0.4.25 beta

- Make normal console gain, input switches, output routing/mono/reference and
  mixer edits live; remove the separate Apply rows and prototype explanations.
- Consolidate muted startup, displayed input gains, routing/mixer setup and
  physical knob activation into one explicit Initialize muted action.
  Phantom power is never replayed by setup.
- Add a bundled native guide under Help → OpenDuet Guide and read-only
  Diagnostics. Keep a compact status line and meaningful control tooltips.
- Preserve fixed 2 dB keyboard volume, independent quick-mixer windows and
  isolated native meter drawing.

## 0.4.24 beta

- Use fixed 2 dB normal keyboard steps rather than the legacy Core Audio
  scalar-to-dB curve. Recover coalesced native steps and resynchronize the HUD
  after USB acknowledgement; preserve mute and −64…0 dB bounds.
- Default-output notifications establish a fresh HUD baseline from known
  hardware state before accepting volume changes, including rapid route changes.

## 0.4.23 beta

- Bridge macOS master volume/mute changes to the verified Main Out USB controls
  only while Duet USB is the default output and Main Out is initialized.
- Synchronize the native HUD from known output state; never import stale system
  volume during activation. Headphones, inputs and phantom power are untouched.
- Add a Settings switch, event-driven listeners, feedback suppression and
  tests for default-device changes, disabled/unknown state and command isolation.
- No keyboard interception, Accessibility permission, new driver or polling loop.

## 0.4.22 beta

- Prepare an MIT-licensed source release with current setup, recovery,
  contribution and validation documentation.
- Add a single offline regression command and release artifact checksums.
- Fix the locally reproduced Hide Mixer termination by dismissing only the console
  through SwiftUI and keeping the application alive after the last window closes.
- Keep window show/hide separate from Quit, which now lives in More actions.
  Add distinct accessibility identifiers and native window lifecycle checks.
- Preserve meter render caches across unchanged view updates and allow visible
  quick-mixer meters when the main application is hidden.
- Preserve the dark four-channel quick mixer from 0.4.19, with shared USB
  ownership, native vertical meters and a Settings switch for the menu item.
- Retain the blue/green app mark, bold OLED typography, simplified overview,
  focused channel view, phantom ring and physical knob/touchpad handling.
- Retain native meter rendering, cached labels and hidden/unchanged frame
  suppression for low control-app overhead.

This is a community testing beta, not a feature-parity certification.
Control-state restoration after sleep still requires setup in the app.
Direct-monitor/routing completeness, calibrated analog behavior, endurance
and original-stack performance comparison remain open. Local packages are
ad-hoc signed; Developer ID signing/notarization is not configured.
