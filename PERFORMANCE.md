# UI efficiency measurements

Percentages below represent **one CPU core**, not total machine capacity.
These are short local CPU-time samples, not a controlled DAW benchmark or
recording-quality/endurance test. Audio content and sampling windows differ.

| Build / workload | App CPU | USB helper CPU | Sample |
|---|---:|---:|---:|
| 0.4.13, active playback | 36.6% | 0.5% | 10 s |
| 0.4.14, native meter drawing | 15.6% | 1.1% | 20 s |
| 0.4.15, cached native text | 11.8% | 1.1% | 20 s |
| 0.4.16, unchanged-frame suppression, foreground | 9.9% | 0.9% | 10 s |
| 0.4.17, active foreground | 11.3% | 1.0% | 10 s |
| 0.4.17, app hidden, audio/control/OLED retained | 4.1% | 1.3% | 10 s |

The active comparison used a collapsed raw diagnostic panel, live hardware
screen, zero input gains, Playback 1–2 routes, Main −16 dB and Headphones
−25 dB unmuted. The user confirmed smooth app meters, hardware knob/screen
synchronization, and correct refresh after hiding/reopening 0.4.17.
Earlier quiet-input results were much lower and must not be presented as
active-playback results. An earlier minimize sample was inconclusive; the
final hidden sample used Cmd-H with no app reinspection during measurement.

## Changes

- Meter updates no longer invalidate the static SwiftUI console/knobs.
- Live readouts draw in small layer-backed AppKit views.
- Text runs are cached with a bounded cache; appearance changes clear it.
- Unchanged visible values/pixels do not request another repaint.
- Hidden/minimized/occluded views skip meter invalidation and refresh when
  visible again. USB polling, peak tracking and the physical OLED continue.
- Distribution builds are optimized. Sampling, the 33 ms smoothing clock,
  peak/clip holds and hardware-screen cadence remain unchanged.

## Reproduce

Run the following locally while the installed app is running:

```sh
python3 tools/measure-cpu.py --seconds 20 --label 'Describe signal and window state'
```

Keep rates, gains, routing, signal content, window size and diagnostic-panel
state consistent. Warm up first. Avoid screenshots, accessibility inspection
and control interactions during the sample; inspection can reactivate a
hidden window. Check active signal and meter motion before and after each
sample. Hidden and visible workloads should be reported separately.

Further opportunities remain: raw diagnostics at a lower update cadence,
physical-screen rendering/transfer work, and sustained active-input/playback
measurements. Full control restoration after sleep remains a separate gap.

## Quick-mixer release preflight — 0.4.19

With playback observed in the console, a 10.01-second sample measured
7.5% of one core for the app and 0.3% for its helper. With playback and an
open quick mixer confirmed by the tester, a separate 10.02-second sample
measured 16.6% app and 0.3% helper. The full console may also have remained
visible behind the popover. These short samples are not matched music
segments, an isolated-popover benchmark or an original-driver comparison.
The 0.4.20 candidate retains render keys across unchanged SwiftUI rebinding;
its active and hidden measurements must be recorded separately.

## 0.4.22 background playback

After the tester closed both the console and quick mixer and confirmed music
was still playing, a 30.02-second CPU-time sample measured 5.4% of one core
for the app and 1.4% for the helper (6.8% combined). No UI or audio commands
were issued during the interval. The controller remained running. This is a
short background-control sample, not DAW load, analog latency, endurance or
an original-stack A/B measurement.

## 0.4.22 quick mixer only

With the main console closed and the quick mixer open, the tester confirmed
continued playback. A 30.02-second sample measured 10.7% of one core for the
app plus 1.2% for the helper (11.9% combined). A read-only UI check afterward
confirmed a connected popover, active Main Out signal and muted headphones;
output state was initialized, not merely unknown drafts. No UI actions were
sent during the sample. This and the 6.8% background result are short control
stack measurements; shared audio-service/DAW work is excluded. Differences
from earlier versions are not a matched-track benchmark. Original-stack
parity and analog latency remain unproven.
