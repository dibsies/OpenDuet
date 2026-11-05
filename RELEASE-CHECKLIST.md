# 0.4.28 beta release checklist

This checklist covers the local enthusiast beta. It does not certify full
feature parity or original-driver performance. Publication is a separate step.

## Automated and artifact checks

- [x] Protocol guards, partial-failure handling and persistent session framing.
- [x] Console lifecycle, no automatic setting replay, linked gain and quick controls.
- [x] Input/output encoders, mixer math, meter decoding/ballistics and display geometry.
- [x] Physical control state machine, native meter rendering and privacy fixtures.
- [x] Reversible vendor quarantine/restore tool transaction tests (temporary fixtures only).
- [x] Candidate release build, signature, disk-image and checksum verification.
- [x] Source ZIP/app privacy patterns and fresh anonymous snapshot history check.

- [x] Keyboard bridge startup/echo suppression, mute, default-device gating and Main Out-only command tests.

## Observed on the development device

- [x] Vendor-free clean boot; native 2-input/4-output 96 kHz duplex callback test.
- [x] Microphone capture and gain response; main-output listening.
- [x] Physical selection/gain direction, dim touchpads, display and meter legibility.
- [x] Sleep/wake screen recovery with explicit setup afterward.
- [x] Four-channel quick mixer layout; Settings switch is present.
- [x] Menu-item disable/re-enable through the native Settings window.
- [x] Installed show/hide confirmation after switching to SwiftUI console-scene dismissal.
- [x] Active playback CPU sample with the quick mixer open and closed.

- [x] Installed 0.4.28 Up/Down/Down sequence, no unexpected mute; −60 dB/mute off verified.
- [ ] Rapid/held keyboard presses and standalone Mute on the final build.
- [ ] Fresh final-build DAW recording (deferred for this experimental beta).

## Before claiming feature parity or a stable release

- [ ] Validate both line modes, headphone output, phase, Soft Limit and line reference.
- [ ] Validate both output playback routes and hardware direct-monitor mixing.
- [ ] Measure analog round-trip latency, dropouts and longer recording/playback sessions.
- [ ] Controlled original-stack performance comparison (currently deferred).
- [ ] Supported macOS/hardware matrix beyond the single development setup.
- [ ] Distribution signing/notarization if using a Developer ID release channel.

## Public sharing

- [x] Review the fresh public snapshot; private development history excluded.
- [x] Review source filenames and packaged contents; personal media excluded.
- [ ] Review GitHub account/profile visibility before publication.
- [ ] Confirm the chosen repository/destination and publish only reviewed artifacts.

Preserve vendor recovery copies and the previous app locally. Do not include
system reports, vendor binaries, private history, recordings or user photographs.
