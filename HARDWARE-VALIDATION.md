# Hardware evidence and limits

This is a condensed record for the first public beta, 0.4.28. Testing used
one Duet 2 USB (VID:PID 0c60:0007) on Apple Silicon/macOS 27.2. Device serials,
raw captures, recordings, machine details and local recovery paths are not
included. A successful USB transaction is not proof of analog behavior.

## Demonstrated during development

- Vendor-free restart with Apogee components quarantined: no matching vendor
  processes/codeless personalities observed; native 2-input/4-output discovery.
- Native 96 kHz duplex callback test: 403 callbacks, 206336 frames in each
  direction, silent output; 44.1 kHz restored. This is not a fidelity test.
- Earlier microphone capture and gain-response measurements. The final
  0.4.28 recording path has not been retested in a DAW.
- Main-output music listening and attenuation; physical knob selection,
  clockwise/counterclockwise gain/level control and app/display synchronization.
- Input source readback, microphone/instrument display symbols, phantom-power
  indication, touchpad Dim actions, readable focused screen and smooth meters.
- Sleep/wake screen recovery. Lost control state requires Initialize muted;
  saved phantom power and audio settings are never replayed automatically.
- Independent quick-mixer/main-window show/hide, menu-item setting and Dock icon.
- 0.4.28 keyboard sequence: unmute at −58 dB, Up, Down, Down with pauses;
  expected −58 → −56 → −58 → −60 dB, with audible playback maintained.
  Read-only inspection afterward confirmed −60 dB and system mute off.

## Still unverified or incomplete

- Fresh end-to-end DAW recording on the final build; both analog inputs and
  sustained recording/playback at each supported rate.
- Full analog validation of line references, headphone output, Soft Limit,
  phase, mono, every output source and direct-monitor mixer combination.
- Rapid/held keyboard presses and standalone Mute on the final build.
- Calibrated analog round-trip latency, dropouts, endurance and a matched
  comparison with the original Apogee stack.
- Other Duet generations, Intel Macs and macOS releases beyond the test setup.

Input meters represent ADC levels. Playback meters represent source levels;
output meters calculate post-control levels and do not measure output jacks.
See BETA-SCOPE.md, PERFORMANCE.md and RELEASE-VERIFICATION.md. These limits do
not prevent an experimental beta, but preclude a complete feature-parity or
stable-production claim.
