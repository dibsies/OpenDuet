# Original Apogee versus OpenDuet: comparison protocol

**Parity is not established.** Current measurements compare OpenDuet builds.
Do not describe lower OpenDuet CPU as a win over the original Apogee stack.

The preserved Duet USB override bundle contains no executable; its
personalities use AppleUSBMergeNub to add properties including timing hints.
Both streaming architecture and actual/reported timing must be distinguished
from the CPU used by the control interface and background services.

## Controlled CPU comparison

Use the same Mac, macOS, attached interface, rate, buffer, routing, input gain,
phantom state, playback source and signal content. Keep the same window size
and meter/hold behavior as closely as the applications permit. Warm up first.
No builds, screenshots or accessibility inspection during a timed sample.

Run at least three 30-second samples per case and report their range/median:

1. Control GUI visible, active playback and input signal where available.
2. Control GUI hidden, same audio workload and physical display active.
3. GUI closed with the controller/service state explicitly documented.

For each stack, sample its entire control group, not just the visible app:

```sh
python3 tools/measure-cpu.py --stack openduet --include-system-audio --seconds 30 --label 'Describe the exact workload'
python3 tools/measure-cpu.py --stack apogee --include-system-audio --seconds 30 --label 'Same workload and window state'
```

Compare OpenDuet plus its helper against Control 2 plus Glue and Messenger.
Report coreaudiod/usbaudiod separately: they are shared services, and not all
their work can be attributed to this interface. Preserve the roles actually
running; a closed GUI must not be represented as a foreground GUI sample.
The sampler reports no usernames, hostnames, media titles or process IDs.

## Recording and playback comparison

At minimum compare 44.1, 48 and 96 kHz with identical supported DAW buffer
settings (for example 64, 128 and 256 frames where accepted by both stacks).
Record the actual rates, device/stream latency and safety offsets using the
read-only tools/audio-timing-report.c utility. It changes no rate, buffer,
USB setting or stream state, and reports no device UID/serial.

Reported latency is not measured analog round-trip latency. Use a proper
output-to-input loopback for sample-offset/round-trip measurements; compare
recorded alignment under the same conditions. Keep phantom off on the loop
input and establish an attenuated output before connecting the loop.
A loopback cable is not required for the first CPU comparison.

Use the same representative DAW session for sustained duplex tests. Compare
CPU, buffer underruns/dropouts, recording alignment and stability over a
meaningful run; a two-second silence callback test is not a substitute.
Direct monitoring latency is also distinct from DAW round-trip latency.

## Original-stack baseline requires a controlled swap

The vendor installation is currently quarantined after a verified clean
restart. All 11 original components and recovery copies verified again.
OpenDuet's present working installation should be preserved.

Before a true full-stack baseline, arrange a maintenance window, save work,
and turn off speakers/headphone amps. Release OpenDuet USB and restore the
verified original components using the existing local recovery procedure.
Glue may load its saved gain, phantom and output settings, so inspect and
match those settings before enabling monitoring. A restart/reattach may be
needed to make the original timing personalities active. This changes the
working stack temporarily; it is not a read-only measurement step.

After capturing the baseline, stage the vendor-free setup again using a
fresh verified recovery session if original files changed. Restart and
verify no vendor services/codeless personalities remain before final
OpenDuet comparisons. No firmware, startup-security or kernel-cache changes
are part of this plan. Administrator authentication must happen locally.
Do not run a stack swap automatically from the benchmark tools.

## Publication gate

Publish only reviewed, deidentified result summaries, never raw registries,
recordings, vendor bundles/installers, private history or recovery folders.
Keep required third-party attributions. See PUBLICATION-PRIVACY.md.

## Current status

The user chose to keep OpenDuet running and defer the original-stack swap.
No vendor component was restored or launched. Original-stack CPU, measured
round-trip latency and sustained DAW parity remain unverified.

The read-only native baseline captured 44100 Hz / 512 buffer frames, with
2 input and 4 output channels at 24-bit physical / 32-bit virtual formats.
Reported device latency was 68 input / 13 output frames; safety offsets
were also 68 / 13; reported stream latency was zero in both directions.
These properties must not be presented as measured analog latency. The
512-frame playback configuration is not a low-buffer recording comparison.
