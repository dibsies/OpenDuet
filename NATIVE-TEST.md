# Native audio test and recovery

## Offline evidence

The installed DuetUSBOverideDriver.kext 1.1.0 is codeless. Its signed bundle
contains a plist and signature, with no executable. All three matching
personalities target 0c60:0007 and use Apple's AppleUSBMergeNub. The
device personality merges naming metadata. The configuration 1 stream
personalities merge the name, sample latency, and sample offset. This
makes round-trip latency and DAW recording alignment important acceptance
checks even if all channels stream using the native driver.

ApogeeGlue is a universal user-space executable with Duet II-specific
input gain, analog reference, monitor handlers, encoder and OLED state,
and change-processing identifiers. These are static clues to where to
trace next. They do not establish the USB request encoding or prove which
code runs on product 0007. The installed DuetII settings XML is a candidate
for a private state backup. Keep it and any raw capture out of Git.

## Test stages

1. In the normal desktop session, save and close audio work. Record the
   normal Control 2 and Audio MIDI Setup state, including gain, input
   modes, phantom, mixer routing, sample rate, and default devices. Back
   up the settings and retain the matching installer privately. Establish
   a known-good mic, instrument, main and headphone playback baseline.
2. For a separately approved maintenance window, record the original
   loaded and startup-enabled states of Glue and Messenger. A temporary
   helper-only stop can test whether audio survives release of USB
   ownership while leaving the codeless override present. Verify ownership
   and stream bindings after any reconnect. The local Stop shortcut also
   changes automatic startup, so it is unsuitable as-is for an isolated
   helper-only test.
3. Prefer a clean compatible macOS installation on separate test media
   for the native-only test. Keep the working boot volume and its Apogee
   installation intact. Compare both input channels and all four playback
   channels, speaker/headphone routing, sustained duplex streaming, sample
   rates, latency and reconnect. Use known safe input and monitor levels.
   Keep phantom-power and hardware-control tests separate from this baseline.
4. Stop if the device disappears, the channel inventory changes unexpectedly,
   streaming glitches, or routing or levels become unsafe. For a helper-only
   test, restore the captured service states, reopen Control 2, and verify
   the original routing and audio baseline. For the separate-install test,
   boot back into the original volume and confirm that Control 2 and the
   baseline work there. The existing Start and Restore Startup shortcuts
   serve different startup policies and have not been verified here.

The next protocol milestone is tracing a Duet II status getter to its USB
transport in the installed executable and verifying the product match and
full request tuple offline before considering an on-device read. There is
currently no verified command allowlist for 0007.

## Live binding checkpoint

The discovery utility confirmed Apple usbaudiod interface clients on
configuration 1 interfaces 0, 1, and 2 while ApogeeGlue retained exclusive
device ownership. Interface 3 (DFU) had no Apple audio client. This is
direct evidence of separate Apple stream bindings and vendor device
ownership in the existing setup. It does not establish that the vendor
helper is dispensable or that a second control client can coexist.

The arm64 Glue binary is stripped. Generic IOKit call imports are visible,
but they do not identify the USB setup packet or its caller. Treat an
unresolved call or immediate constant as insufficient evidence for a
request. The next useful static artifact is a trace from a model-specific
status handler through the transport wrapper, including the source of
each setup packet field.

Audio MIDI Setup in the interactive desktop session showed Duet USB with
2 inputs and 4 outputs at 44.1 kHz, with a 24-bit integer output format.
Built-in microphone and speakers were the system defaults. This resolves
the inventory discrepancy with the development runner. Signal flow and
recording alignment still require separate tests.

The idle registry snapshot exposed alternate 0 with zero endpoints on the
two streaming interfaces. This describes the visible idle alternate only.
The complete endpoint descriptors and alternate settings remain unknown.
The registry also exposes the merged timing properties. At 44.1 kHz the
advertised input/output latency values are 24/25 samples and the input/output
offsets are 56/22 samples. These are registry values rather than measured
round-trip latency. Save a snapshot before and after any approved binding
test to establish whether the properties changed.

## Reuse boundary

[Duetbar](https://github.com/mulhoon/duetbar) already implements the
day-to-day macOS controls over the installed ApogeeGlue service. Use that
implementation as the vendor-backed reference instead of building another
Glue client. Its read-only state and meters can help establish a baseline,
but a Glue-backed test cannot establish independent control. Focus protocol
research on the USB transport and the undocumented mixer and physical
control behavior. Keep native audio testing separate from that work.

### Verified Glue handshake

The installed helper responded on IPv4 loopback port 53435 to the
read-only greeting used by
[Duetbar's GlueClient](https://github.com/mulhoon/duetbar/blob/463c35f0881dfb5e40270867a1e946db6ad463bd/Sources/GlueClient.swift).
Use the upstream source as the framing reference. The magic is a
little-endian integer, so the first four transmitted bytes are
`2c 9e b4 f2`. Sending the integer in the opposite byte order timed out.

The reply used opcode 0x66 and was 1,255 bytes. Its zlib stream began
four bytes into the payload and expanded to 3,510 bytes containing a Duet
label. The brief connection timed out waiting for a further frame, so
meter delivery and signal flow remain unverified. The probe sent only
the greeting and retained no raw state. This confirms the upstream IPC
path on this installation, independently of Core Audio device discovery
in the development runner.

Duetbar's upstream Swift parser also accepted the live hardware tree.
It exposed two analog input nodes and the Main Out and HP nodes, including
a routeSource property on each output. This confirms routing state is
available through Glue even though Duetbar's published write map omits it.
A single snapshot cannot establish what each route value means or identify
its setter. No settings messages were sent.

### Mixer and physical-control state

The upstream parser exposed Mixer 1 and three channel nodes in the local
configuration schema. The live tree and saved settings both contained
`channel2.routeSource` and two touchpad nodes, each with an `actionButton`
property. The saved output route fields and channel 2 route field each
held 402653184 in the inspected snapshot. An identical raw value across
fields does not establish identical semantics. No setter ID or raw USB
request was verified.

Map the routing values by comparing state immediately before and after
a single Control 2 route change. Capture the initial route in Control 2
and restore it immediately after the read. Changing an output to the
hardware mixer may make a live input audible, so use muted or disconnected
physical monitors for that comparison. Touchpad assignments can be
compared separately. Neither test requires constructing a USB packet.

Control 2 independently displayed Playback 1–2 for Main Out, headphones
and the playback return in the baseline where Glue reported 402653184
(`0x18000000`) for all three. This verifies the baseline label for those
fields on this installation. The route menu did not open through desktop
automation, so the Mixer 1 and Playback 3–4 values remain unknown.

### Recovery checkpoint

Captured a private copy of the installed DuetII settings XML, its SHA-256,
both Apogee launch daemon definitions and service states, and a USB
discovery snapshot before any interruption. Both Glue and Messenger were
running and startup-enabled. Restore those same states if a later helper
test changes them. The settings copy is a reference for recovery and has
not been restored or tested as an installer. No separate test volume was
mounted when the checkpoint was taken.

Use a known signal on each analog input and independently observe both
stereo output pairs for the baseline. Device enumeration alone cannot
establish analog signal flow. Record pass/fail for each direction and pair,
then use the same sources and observation points in the clean-boot test.

### 96 kHz format check with Glue stopped

After a USB reconnect with Glue unloaded, the identifier probe returned
eight bytes. Audio MIDI Setup accepted 96 kHz and retained 2 inputs and
4 outputs. The input stream showed 2-channel, 24-bit integer format.
The original 44.1 kHz setting was restored before ending the test window.
The Apogee override was still installed. This verifies format selection
and enumeration only. No recording, playback, or timing was measured.
