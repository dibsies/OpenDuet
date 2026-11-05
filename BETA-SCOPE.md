# Feature parity release gate

The next user test release must expose a coherent input, output and mixer
interface with live hardware state. A successful USB transaction alone
must not be displayed as verified hardware state.

**Current verification limits:** earlier microphone capture/gain response,
main-output listening, hardware controls/screen, vendor-free clean boot and
native 96 kHz duplex callbacks have been demonstrated. Final-build DAW recording,
detailed analog routing/mixing and endurance remain unverified. See
[hardware evidence](HARDWARE-VALIDATION.md).

| Area | Required behavior | Current gap |
|---|---|---|
| Inputs | Both line modes, mic, instrument, gain, 48 V, Soft Limit, phase, grouping | Mode snapshot and same-session gain guard added; offset-preserving linked gain implemented; remaining readback and physical validation remain |
| Outputs | Independent level, mute, dim, mono, line reference | Command UI and paired transfers implemented; readback and physical validation remain |
| Routing | Playback 1–2, Playback 3–4, mixer for main and headphones | Named selectors, UI and packed command implemented; readback and hardware validation remain |
| Mixer | Input and playback return levels, pan, mute, solo, stereo linking, mixer master | Coefficient math, paired bank transport and pending-state UI implemented; named routes and stereo linking implemented; hardware validation remains |
| Physical controls | Encoder behavior, touchpad assignment, physical change synchronization, display behavior | Live encoder selection/output changes and both touchpad Dim actions confirmed; other targets pending |
| Metering | Both analog inputs, playback, speakers, headphones | Input scales/peaks/headroom and smooth app/OLED motion confirmed; Playback 1–2 source observed; post-control output display is calculated, not analog-calibrated |
| Audio | Native capture/playback, supported sample rates, duplex at 96 kHz | Native 96 kHz duplex callback test passed and restored 44.1 kHz; fidelity, analog output and endurance tests remain |
| Lifecycle | Discovery, disconnect, reconnect, sleep/wake, configuration persistence, explicit errors | Persistent connection, retry, sleep/wake and pending profile implemented; screen intent recovery is implemented/tested offline; user confirmed screen recovery after sleep; transparent control-state restoration remains |
| Distribution | One macOS app, dark UI, helper included, installer/recovery guidance | Dark console and source-inclusive beta package; distribution signing/notarization remains |

The 0.4.28 package is an enthusiast testing beta. Older DMGs are superseded.
Full feature parity is not certified; the physical validation gaps above
remain open.
