# OpenDuet 0.4.28 beta validation record

This first public beta targets Duet 2 USB 0c60:0007. It is not a claim of
complete feature parity, stable production readiness or original-driver
performance parity. See HARDWARE-VALIDATION.md for physical evidence/limits.

## Automated checks

The offline suite covers command framing and guards, startup ordering,
partial failures, console/control lifecycle, source/gain/phantom isolation,
linked gain, physical event handling, mixer coefficient math, meter decoding,
ballistics, display geometry, native meter drawing and window actions.
Vendor quarantine/restore tests use temporary fixtures, not system components.

Keyboard tests cover initialized-state synchronization, duplicate/echo
suppression, default-output gating, unknown/disabled state, property-write
ordering and mute-first/volume-later notifications. Output guard tests cover
single jumps greater than 25 dB, entry to 0 dB, ordinary adjustments,
cancellation, stale proposals and physical-knob integration.

## Installed behavior

The tester confirmed independent quick-mixer/main-window show/hide,
Settings menu-item toggle, hardware screen/knob, readable OLED controls,
main-output listening and sleep/wake screen recovery during development.
Setup after lost control state remains explicit.

On 2026-11-05, the installed 0.4.28 keyboard test passed: unmute at −58 dB,
Up, Down, Down with pauses, reaching −56, −58 and −60 dB without unexpected
silence. The trace showed native mute-first events followed by scalar changes
about 80 ms later; the bridge retained its unmuted target. Read-only inspection
confirmed −60 dB/mute off afterward. Rapid repeats and standalone Mute still
need live validation on this build. Earlier attempted fixes did not pass;
this result is specific to the stated sequence.

## Performance context

The 0.4.22 baseline measured, over 30.02 seconds, 6.8% combined app/helper CPU
with both views closed and playback active, and 11.9% with only the quick
mixer visible. Percentages are of one CPU core. These are earlier-build,
single-machine short samples, not final-build guarantees or an Apogee A/B
comparison. See PERFORMANCE.md and APOGEE-COMPARISON.md.

## Release artifact requirements

Build from a clean, neutral-history public snapshot. Package matching source,
source revision, MIT/upstream notices, guide, installation/recovery instructions
and beta limitations. Audit source filenames/contents, app binaries and all
DMG payload files for personal data, not just the development checkout.
Strip debug-map paths, verify ad-hoc signatures and the read-only disk image,
and publish hashes identifying the reviewed artifacts. The installed test
candidate and release must have matching executable code sections when only
documentation/source-history metadata changes.

The binary beta is ad-hoc signed and not notarized. Do not change macOS
security settings to run it; building from source is an alternative. Recovery
copies, private history, recordings, media, system reports, vendor binaries
and local quarantine sessions stay outside the public snapshot and artifacts.
