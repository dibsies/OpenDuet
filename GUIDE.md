# OpenDuet Guide

OpenDuet controls the Duet 2 USB while Apple's native audio system handles recording and playback. Normal control edits take effect immediately.

## First connection

Connect the Duet, then choose **Connect USB** if needed. If another service owns the device, OpenDuet reports that it is busy instead of taking over.

Choose **Initialize muted** once. Outputs start muted at −64 dB. Setup applies the shown input gains, output routing/reference and mixer settings, and enables the physical knob. **Phantom power is unchanged.** Raise output levels and unmute deliberately.

## Live input controls

Source selection, gain, 48 V, Soft Limit and phase take effect when edited. Mic and instrument have separate saved gains. Line inputs use fixed reference levels, so their gain dial is disabled.

Enable **48 V** only for equipment that needs it. Returning to Mic mode never automatically enables phantom. Switching a confirmed phantom-powered input to another source disables phantom first. A blue ring on the device microphone symbol indicates an enabled phantom command from the current session.

**Link input gains** preserves the established gain offset between compatible mic/instrument channels, including when either channel reaches its gain limit.

## Outputs and direct monitoring

Main Out and headphones have independent level, mute, dim, mono and source controls. Edits apply live after initialization. Dim adds attenuation without changing the stored level.

Choose **Playback 1–2**, **Playback 3–4**, or **Mixer** as the output source. The direct-monitor mixer blends the analog inputs and the selected playback return. Level, pan, mute, solo, stereo link and master edits are coalesced into live updates; no Apply button is required. Route an output to Mixer to hear it.

The **main line reference** changes the analog output reference between +4 dBu and −10 dBV. This can change audible output level. It is separate from the master attenuation dial.

## Output volume guard

Drag a dial vertically to adjust relative to its current value. Hold **Shift** for finer control; clicking alone does not change the level.

Main Out and headphones retain their full −64…0 dB range.

A single increase greater than 25 dB is held for explicit confirmation. Entering full output (0 dB) always requires confirmation, even for a small increase. Ordinary adjustments do not repeatedly prompt. The existing level remains in effect until confirmed. Decreases always remain available. The same guard covers the app, quick mixer, keyboard and physical knob. A stale proposal is rejected if the level or connection changes.

Collapse **Direct monitor mixer** using its disclosure arrow when you do not need it. Its open/closed state is remembered.

## Keyboard volume

Enable **Keyboard volume controls Main Out** in OpenDuet Settings. It is active only while Duet USB is the macOS default output and Main Out is initialized. Normal keyboard volume presses change Main Out by **2 dB**, bounded to −64…0 dB; mute is independent. Headphones and inputs are not changed.

OpenDuet keeps the native system volume/HUD synchronized with its known output state. The bridge observes Core Audio controls rather than intercepting keys, so other macOS master-volume changes are relative adjustments too. Use OpenDuet's dial to choose an exact absolute dB level. No Accessibility or Input Monitoring permission is needed.

## Meters and headroom

Input meters show the ADC signal after preamp gain. Use the held peak and headroom reading to leave room below clipping when setting recording levels. Peak/Over Hold can be Off, 2 seconds or Infinite; **Clear peaks & clips** resets holds on the app and hardware screen.

Playback meters show the source even when outputs are muted. Main/headphone meters calculate the routed signal after level, mute and dim; they do not measure the analog output jacks. Mono peaks are a conservative bound.

## Hardware knob and touchpads

Press the knob to select Input 1, Input 2, Main Out or headphones. Turn clockwise to increase and counterclockwise to decrease the selected value. The device temporarily focuses that channel, then returns to its overview. Physical gain adjustment is available after initialization establishes the shown gains.

Assign touchpad A/B actions in the sidebar. Assignments are host-controlled and require OpenDuet to be running. Unknown control values are not raised or toggled automatically.

## Quick mixer and windows

The menu-bar icon opens the four-channel quick mixer. **Hide mixer** dismisses only the full console; it does not quit OpenDuet or stop audio. Reopening the menu icon shows the quick mixer independently. **Show mixer** restores the console.

Settings → **Show quick mixer in menu bar** removes/restores the menu item without stopping the controller. Quit is in the quick mixer's **More actions** menu and the standard application menu. Closing a window does not quit the controller.

## Sample rate, sleep and reconnect

Sample-rate selection takes effect immediately and interrupts audio. Stop recording and playback before changing it. The available rates come from the native audio device; 96 kHz native duplex has been demonstrated on the development setup, not calibrated for every workload.

Sleep and unexpected disconnect release the USB session. OpenDuet retries discovery and restores the screen, but does not automatically replay saved audio settings or phantom power. If state was lost, choose **Initialize muted** to establish the shown gains and a muted output state again. **Release USB** cancels retries until Connect USB is chosen.

## Troubleshooting and privacy

Use **Diagnostics** for the device inventory, last operation details and raw meter lanes. A failed update can leave earlier commands applied; reinitialize muted before resuming if the control state is unknown. Preserve your vendor installer and verified recovery copies while testing. OpenDuet does not remove vendor software, change firmware or alter system security.

Diagnostics can contain local device names and paths. Review them before sharing. OpenDuet has no account, network client, telemetry or automatic uploads. Release source and app artifacts are checked for personal information, and private development history is not published.

## Beta validation limits

This is an enthusiast beta for Duet 2 USB 0c60:0007. The current test setup is Apple Silicon/macOS 27.2. Native capture, gain response, main-output listening, display/knob behavior and a 96 kHz duplex callback test have been demonstrated.

Some line/headphone controls, detailed routing/direct-monitor behavior, calibrated analog latency/fidelity and longer endurance tests remain incomplete. USB command success is not analog verification. Original-driver CPU/latency parity is not established. Local betas are ad-hoc signed and not notarized; no system security changes are required by the app.
