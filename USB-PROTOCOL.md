# Duet II USB protocol evidence

Offline analysis of the installed ApogeeGlue arm64 slice, whole-file
SHA-256 `a8db9fed76277e251e1c0367aceeb4d004f64b9fbd4a7b86c92e6d8548485b54`.
Addresses below are unslid virtual addresses in that binary.
These notes record successive investigations. Early unresolved items and
replay restrictions are historical; later sections and HARDWARE-VALIDATION.md
record the current implementation and physical evidence.

| Address | Evidence |
|---|---|
| `0x100036810` | Wrapper logs a vendor IN request and sets request type `0xc0`. |
| `0x100036978` | Wrapper logs a vendor OUT request and sets request type `0x40`. |
| `0x10000d1e4` | Logging identifies the Duet II output attenuation handler. |
| `0x10000d29c`, `0x10000d2b0` | Handler passes opcode `0x33` twice into a one-byte helper, with different indices. |
| `0x100188918` | Helper dispatches through virtual slot `0x18`, passing length 1 and value 0. |

Both vendor wrappers put the request, value, index, length and data pointer
at offsets 1, 2, 4, 6 and 8. An offline C layout check against the installed
SDK confirmed those offsets for IOUSBDevRequestTO and confirmed
DeviceRequestTO at slot 0xf0 of IOUSBDeviceInterface197, the slot used by
both wrappers. This establishes the wrapper ABI. The concrete vtable for
the Duet II handler's dispatch at slot 0x18 remains unresolved.

[Take Control](https://github.com/stefanocoding/take_control/blob/master/take_control.py)
also uses opcode 0x33 for output level on product 0016. The vendor handler
shows extra dispatch and index behavior, so matching the opcode alone is
insufficient to port the Linux implementation to 0007. Duetbar's local
Glue property IDs are a separate layer and do not fill this gap.

The next static check is to resolve the concrete object at Duet II
handler offset 0x428 and follow its virtual dispatch into the vendor
wrappers. Establish product selection, direction, both indices, data
encoding, and the purpose of the repeated call before adding an
executable command. No request in these notes is approved for replay.
Physical audio and phantom-power validation are deferred.

## Attenuation payload and dispatch

The USB transport constructor stores vtable address `0x1002b1368`
at `0x100037d00`. The arm64 image's slots at offsets `0x10` and
`0x18` point to `0x100036810` (vendor IN) and `0x100036978`
(vendor OUT), respectively. This resolves direction for that concrete
transport. The remaining provenance check is to prove the specific
Duet II constructor path installs this object at offset `0x428` for
PID `0007`.

The named attenuation handler computes one byte from the negated level,
rounded to nearest with ties away from zero. When dim is active it
subtracts 15 dB before negating and rounding. Both calls receive the
same byte pointer. For handler output index 0, the calls pass USB indices
1 then 2. For a nonzero handler output index, they pass 3 then 4.
The helper supplies length 1 and value 0. The helper also retries on
failure, independently of the handler making two calls for the pair.
These observations explain why using a single output-level request from
the related Linux project would omit part of the vendor sequence.

No corresponding Duet II status getter was established in this pass.
The candidate transfer remains documentation only, pending the
product-to-object trace and eventual device validation.

## Reproducing the layout check

Run `tools/verify-glue-layout.sh <ApogeeGlue executable>` with Xcode
command-line tools and Python 3. The script checks the binary hash before
reading the arm64 transport slots and the Duet II primary RTTI reference.
It extracts the slice to a temporary directory and does not launch the
binary. The primary Duet II vtable address point is `0x1002acbd0`,
immediately after the RTTI pointer. The named Duet II destructor restores
that address point at `0x10000bfd4`. This is a second anchor for finding
the Duet II factory independently of the attenuation log message.

## Product-specific factory trace

The dispatch at `0x10016fb28–0x10016fb54` reads the 16-bit field at USB
object offset `0xa`, subtracts 7 and uses the result to index a 16-bit
jump table at `0x100264e58`. The table sends product 0007 to
`0x100170510` and product 0016 to a different branch, `0x100170ff4`.
The 0007 branch calls the base constructor with the USB object in x1
at `0x10017064c`. The base constructor saves x1 at stack offset 0x38
and copies it into object offset 0x428 at `0x100174df4`. The factory
then installs the Duet II class vtable at `0x100170674`. The named
attenuation handler retrieves that same member to make both calls.

This establishes the product-specific branch and the member's origin.
The exact concrete USB object provenance at the caller of the factory
and a product-specific status getter remain to be verified. The verifier
now checks both jump table entries offline.

## First product-specific vendor IN candidate

The Duet II vtable entry at `0x1002acd00` points to `0x10000b5f8`.
That routine retrieves the USB member at offset 0x428 and calls virtual
slot 0x10 with request 0x31, index 0, value 0 and length 8. The concrete
USB transport uses that slot for vendor IN (0xc0). The routine formats
the returned eight bytes as hexadecimal and combines them with a Duet II
prefix. This is evidence of an identifier read, not an attenuation
status getter. Raw identifiers should stay out of logs and Git.

The USB arrival callback at `0x10016f744` forwards its incoming USB
pointer unchanged to the product factory. The USB enumerator populates
the PID at offset 0xa and installs the concrete transport vtable at
`0x100037d00`. The remaining static provenance link is tracing the
enumerator's delivery of that object to the arrival callback. This
candidate was derived from the installed binary and has not been sent.

## Enumerator-to-factory handoff

The enumerator writes the concrete USB transport vtable at
`0x100037d00`, then places that pointer in its device list at
`0x100038b70` on the append path. The notification routine walks
that list, copies the pointer into its notification list, and puts
the last entry into the callback argument at `0x1000395fc`.
It invokes virtual slot `0x30` at `0x100039618`. The arrival
callback vtable begins at `0x1002b6af0`, with that slot pointing to
`0x10016f744`. The callback dereferences the argument and forwards
the object to the PID factory. Together with the constructor trace,
this closes the static transport chain for the analyzed build.

The identifier request's statically traced setup tuple is
`c0 31 00 00 00 00 08 00` in USB wire byte order. The eight-byte
reply is used to construct an identifier. Actual device behavior,
open/claim requirements under Apple streaming, and coexistence with
ApogeeGlue remain hardware validation questions.

Run `python3 tools/verify-duet-identifier.py` for the synthetic wire
fixture. It checks the setup bytes and the arm64 routine's little-endian
64-bit interpretation of an exact eight-byte reply. Short or oversized
replies are rejected. The fixture has no USB access.

## Live normal-open probe

A single normal USBDeviceOpen attempt with the installed Apogee setup
running returned `0xe00002c5` (kIOReturnExclusiveAccess). The probe
exited before DeviceRequestTO, so no identifier request was sent.
The registry still showed ApogeeGlue as exclusive owner afterward.
This rules out normal device-open coexistence with the current Glue
claim. A helper-release experiment would be a separate maintenance
test with restoration of the previously captured service state.

With Glue fully unloaded, a normal USB open succeeded, the identifier
request returned exactly eight bytes, and USB close succeeded. The
probe discarded the reply. The initial release script raced with
service teardown, so Glue was restored manually and the script was
updated to wait for release and reacquisition. This validates the
identifier query on the connected 0007 unit. Streaming alongside the
independent client remains untested.

## Input control candidates

The Duet II input handlers supply additional candidates to the same
one-byte OUT helper at 0x100188918. At 0x10000ea28 the request is
0x3e, with the input index incremented by one and the rounded gain
as the payload byte. The corresponding sequence at 0x10000ef30
uses 0x34 and the same index conversion. These are consistent with
instrument and microphone gain, respectively, in Take Control's
0016 implementation. The Duet II path at 0x10000f110 sends 0x16 with
a mapped input-mode byte. Trace its input index and all mode branches
before treating it as a complete command. These writes remain untested.

The installed package receipts identify Control, OverrideKext, Glue,
Messenger and TalkbackHelper as separate components. Record their
file lists and verify the local installer before any clean installation
test on the working volume. Releasing Glue alone already permits the
verified direct identifier read, so removal is unnecessary for further
USB protocol experiments.

### Input mode translation

The handler subtracts one from the Glue input source and indexes the
four 32-bit entries at arm64 image offset `0x2647b0`. Read in order
they are 2, 0, 1, 3. Cross-referencing the already verified Glue input
source definitions gives Mic → 2, +4 dBu → 0, −10 dBV → 1, and
Instrument → 3. This is the payload byte for vendor OUT request 0x16.
The input-mode handler passes its captured input index directly,
unlike the two gain handlers which increment their captured index.
The input index capture must be checked independently before replay.

The input-mode callback captures the zero-based channel unchanged.
The two registrations at `0x1000097a8` and `0x1000097b4` call
`0x10000dc30` with 0 and 1. The registration copies that argument
into the callback context at `0x10000ddc8`. Its vtable slot at
`0x1002ad490` points to the mode callback `0x10000f084`, which reads
the low 16 bits of that capture into wIndex at `0x10000f100`.
Therefore the traced mode indices are 0 and 1, while the gain writes
use 1 and 2. A hardware mode write and readback remain untested.

### Phantom-power candidate

The callback at 0x10000f218 takes a boolean, stores it in a single
payload byte, and sends opcode 0x15 through the same OUT helper.
It passes its captured channel directly as wIndex, with value zero
and length one supplied by the helper. Its callback entry is at
arm64 file offset 0x2ad410. The adjacent input-handler registration
captures the zero-based channel used by the mode callback. Verify
the exact property-name binding and device behavior before enabling
this write. No phantom-power request was sent.

The registration at 0x10000dd58 installs callback vtable 0x1002ad3e0
and captures the same channel argument used by input mode. Its invoke
slot (+0x30) points to 0x10000f218. Thus the candidate uses indices
0 and 1. The registered property key is the identifier object at
0x100351628.

Static initialization at 0x1001e0a38–0x1001e0a4c constructs that
identifier from the string phantom, closing the property binding.

### Routing callback

The Duet II routeSource registration at 0x10000d848 installs vtable
0x1002ad6e0. Its invoke slot at 0x1002ad710 points to 0x10000fb24,
which forwards to 0x10000d2e0. That routine reads both output routes
and reaches the one-byte vendor OUT helper with opcodes 0x37 and 0x38.
This traces the 0007 routing path independently of Take Control's
0016 opcode 0x53. The route-to-payload branches remain to be decoded.

The 0x37 payload at 0x10000d524 adds two route contributions.
The second output contributes a base of 0x00, 0x10 or 0x20 for
the three recognized route branches at 0x10000d45c, 0x10000d4a0
and 0x10000d4bc. The latter two compare against globals
0x10035d3b8 and 0x10035d2d8. Their initialization is the next
place to establish the user-facing route labels. Separately,
0x38 takes a boolean from each of the two output nodes, using
the first value in the low bit and the second at bit 4. Its
property key is at 0x100351760 and needs separate identification.

The first output uses selectors 0, 1 and 2 at 0x10000d368,
0x10000d3a0 and 0x10000d3b8. Both output branches compare against
the same three globals in the same order. Therefore the recognized
route pair is encoded as first selector plus 16 times second
selector. Updating one output requires preserving the other selector.
The three globals are in zero-initialized storage in this image, so
their raw route IDs must be recovered from runtime initialization
or a state comparison rather than read from the binary as literals.

The initializer at 0x1001e1050 binds 0x100351760 to the string
`sum`. The paired 0x38 write is therefore output sum-to-mono,
with the first output in bit 0 and the second in bit 4. It is
separate from route selection.

### Reconnect comparison

With Glue unloaded but USB left connected, a normal open succeeded and
the identifier read returned kIOReturnNotResponding. The failure
persisted after five seconds and one retry five seconds later.
In the interactive reconnect test, unplugging and reconnecting USB
while Glue was unloaded produced a successful eight-byte read after
five seconds. Normal close and Glue reacquisition both succeeded.
This is one successful fresh-enumeration run. The underlying cause
and stability during native audio streaming remain unverified.

## Hardware notification polling

The Duet II periodic routine at 0x10000b88c issues vendor IN opcode
0x29, index/value zero, length 29. It dispatches the response through
a callback only when the packet's first byte is nonzero and the USB
wrapper reports success. The callback at 0x10000cab0 inspects flag
bytes and updates properties. This is change notification processing,
so it cannot be assumed to supply a complete initial state.
Polling frequency and whether notifications are consumed must be
verified before adding another reader alongside Glue.

The callback also reads a 16-bit encoder-related quantity at context
offset 0x24, compares it against cached device state, and scales it
by a floating-point factor before changing output properties.
Its exact meaning needs the handler and initialization trace.
This path is independent of the eight-byte identifier request.

## Independent meter read

The routine at 0x10000baf0 issues vendor IN opcode 0x14, index/value
zero, length 20. It swaps each 16-bit word before feeding the meter
processor, establishing ten big-endian lanes on the wire. The conversion
at 0x10000bbe0 divides by 16384, clamps to unity above 0x3ffe, and
uses 20*log10 to obtain dB. Overload is raw > 0x3ffe.
The meter lane selection at 0x100009588 depends on output routes,
so a fixed output label map would be incorrect.

## Independent mixer coefficient path

The common mixer calculation at `0x100097aec` prepares two banks of
four coefficients. Mono inputs use equal-power pan (cosine for left,
sine for right); the stereo return uses squared balance attenuation.
Channel and master dB levels combine with a +12 dB ceiling. Mute and
solo exclusion zero the affected coefficients. Conversion uses a scale
of 8192 and nearest-even rounding, with a 32768 ceiling.

Duet II's writer at `0x100009b8c` serializes coefficients as big-endian
16-bit words. Its calls at `0x100009e0c` and `0x10000a084` issue vendor
OUT request `0x10`, value zero, length eight, indices zero and one.
Left order is input 1, input 2, playback left, zero. Right order is
input 1, input 2, zero, playback right. This differs from PID 0016's
individual mixer-property commands in take_control.

`MixerCoefficients.swift` and `verify-mixer.sh` implement/check this
path offline. The helper validates both banks before opening USB and
reports partial completion explicitly. There is no atomic two-bank
commit or hardware readback claim. No mixer write has been exercised
against the device as part of this implementation.

## Resolved route identifiers and input-mode readback

The static initializer stores `0x18000000` at global `0x10035d398`
(`0x100245f64`–`0x100245f78`) and `0x18000002` at `0x10035d3b8`
(`0x100245f9c`–`0x100245fb4`). These are the first two software
playback pairs. It stores `0x28000000` at `0x10035d2d8` at
`0x100245e38`–`0x100245e4c`, the mixer source. Combined with the
Duet II route handler, this resolves selectors 0 = Playback 1–2,
1 = Playback 3–4 and 2 = Mixer. Output routing packs main in the low
nibble and headphones in the high nibble of request 0x37's single byte.

The exact-PID 0007 implementation in duet2-startup issues an IN 0x16,
value zero, index 0/1, length one, to read back the active input mode.
OpenDuet's `--input-modes` uses that existing implementation as its
reference, requiring complete valid responses from both inputs. Gain
writes additionally read the corresponding input mode in the same USB
session and refuse a write if it is unknown or does not match mic (2)
or instrument (3). This guard is implemented but remains to be exercised
with USB ownership released on the physical Duet.

## Startup/display state machine investigation

REA exposes RTTI for `WaitingForDevice_state`, `InitDeviceSide_state`,
`DefaultRunning_state`, `HomeDisplay_state` and `StartupScreen_state`.
Their state handling confirms host involvement in front-panel display
and physical-control behavior. Waiting-state event handler
`0x100004124`, on events 7 or 2, invokes a 160-by-128 clear operation
through device virtual slot 0x198 and then selects a display state.
The common running handler `0x100004380` processes touchpad assignments,
input source/gain events and output mute/attenuation changes.

The normal settings initializer `0x10000a188` ends with one-byte vendor
OUT request 0xab payload 0, then request 0x25 payload 1, both at index
and value zero (`0x10000b228`–`0x10000b258`). It then emits event 7.
These are normal-startup candidates, not yet implemented or replayed.
Their detailed meanings and ordering with display initialization remain
unproven. Do not send them merely because individual settings transfers
were accepted.

Live evidence now shows the device remained at the A logo after the
independent settings test, while restarting Glue restored its normal
display. USB meter data stayed zero and recorded mic levels were weak.
The next integration work must resolve startup/display operation rather
than treating the current helper as a complete controller.

The startup experiment is now implemented as the narrowly constrained
helper command `--experimental-startup-muted device 1 --apply`. It mutes
all four output channels, attenuates all four to −64 dB, then sends the
two final initializer writes in the traced order. A failed transfer
aborts the sequence. The user explicitly authorized this experiment
after reviewing the uncertainty and recovery path. No display clear,
firmware payload, DFU command or driver modification is included.

Additional offline encoding follows the display clear path at
`0x10000bcf4`: request 0x23 carries two big-endian color bytes, with
start coordinates packed into wValue (x in the high byte, y in the low)
and inclusive end coordinates packed into wIndex. The state handler
uses a 160-by-128 rectangle. `OLEDTransfer` bounds-checks the geometry;
it is not connected to an executor or automatically sent to hardware.

The prefix decoded by `DeviceEvents` is the 29-byte IN 0x29 report.
Its nonzero first byte gates event processing. The next three low bits
trigger the two touchpads and encoder press, and the following two bytes
carry opposite-direction step counts. These fields derive from
`0x10000cab0`, `0x100004380` and `0x100005924`. Physical direction and
event behavior remain to be validated. Unresolved tail fields are omitted.

## Host display transport and session implementation

REA inspection of render queue `0x100003ca8` and transfer thunks
`0x10000befc` / `0x10000bf40` shows a rectangle begins with request 0x21
and at most 64 pixel bytes; subsequent chunks use 0x22, value/index zero,
also at most 64 bytes. The rectangle uses the same inclusive coordinate
packing as fill. Static image headers establish two bytes per pixel.
OpenDuet renders original 160×128 RGB565 artwork and sends 16×8 tiles,
each as one 0x21 and three 0x22 transfers. Its session cache skips unchanged
tiles and invalidates on partial failure or muted startup. No vendor artwork
is redistributed. Display updates require explicit opt-in and remain
physically untested. These newer findings supersede the earlier note that
OLED encoding had no executor.

The normal USB lease now persists across meter/event polls and commands.
Connecting sends only read requests; reconnecting does not replay saved
settings. Hardware actions require explicit enablement and confirmed
applied state. A failed batch invalidates that state. Offline transport
mocks verify startup order, mode guards, short-read rejection, partial
failure, display chunking/cache recovery and session framing.

## Physical display trial and coordinate correction

The first physical trial accepted all 640 display transfers (40960 bytes),
but the user observed the A logo unchanged. This exposed an encoding error:
our initial rectangle fields were reversed. Rechecking the concrete vendor
OUT wrapper `0x100036978` establishes argument a5 at request offset 2
(wValue), and a4 at offset 4 (wIndex). The OLED thunk passes start as a5
and inclusive end as a4. Thus wValue is start and wIndex is end. Earlier
coordinate claims were incorrect; this section and corrected tests supersede
them. The retry changes only these two fields in the already approved
0x21/0x22 sequence. Its transfers completed; visible confirmation is pending.

Read-only samples after the first trial: input modes 2/2, meter bytes
`0000000000000000000000010000000000000000`, event bytes
`02000000000000000000000000000000000100000000000000000008b8`.
No meaning is assigned to the event report's unresolved tail.

The user subsequently confirmed OpenDuet text and muted outputs stayed
visible when the same corrected frame was sent inside a persistent session
with IN 0x29/0x14 polling. The one-shot version displayed briefly then fell
back to A. Retained ownership and regular reads were changed together, so
a specific watchdog mechanism is not yet established. The shipping app's
persistent session provides both. Visible rendering is now physically
confirmed for this original screen; all physical controls are not yet
validated.

## Source meter routing and music observation

Rechecking `0x100009588` shows output source selection uses raw lanes 0/1
for Playback 1–2, 2/3 for Playback 3–4 and 6/7 for the mixer fallback. Input
lanes remain 4/5. With the user playing desktop music to Duet USB, the app's
raw meter view showed lanes 0/1 around −6.8/−9.6 dBFS while lanes 2/3 were
silent. Lanes 8/9 duplicated this sample; their role remains unassigned.
This physically confirms desktop playback signal reaches 0/1, not analog
output or mute/attenuation accuracy. Main/HP display meters select source
lanes from the successfully applied route and remain pre-level/pre-mute.

## Meter tap points and ballistics (0.4.6)

Apogee's original guide (https://apogeedigital.com/pdf/Duet2-UsersGuide-print.pdf,
printed pages 26–27, 30) identifies input metering after A/D and output
metering before D/A, with peak/over hold options. Raw input lanes already
include preamp gain. Never add the gain parameter to their dBFS values.

The raw output-source lanes established above do not measure analog output
after attenuation. At the user's request the default Main/HP presentation
now calculates source dBFS plus the acknowledged level, subtracting 15 dB
for Dim and clearing on Mute. It is labelled calculated, not measured at
the output jack. For mono, per-channel peak envelopes contain no phase
information; the shown result is a conservative peak bound, explicitly
labelled as such. An analog loopback remains necessary for calibration.

REA `0x10008d4d0` computes elapsed seconds times 20; `0x1000a1070`
subtracts that value from displayed level, uses immediate rising peaks,
and applies two-second hold branches. The host processor now uses this
20 dB/s release, with Off/2 seconds/Infinite holds and clear controls.
Mac presentation advances at approximately 30 Hz; OLED updates target
10 Hz and retain dirty-tile encoding. Transport scheduling can limit OLED
refresh. Input full-scale alerts derive from returned ADC meter values;
this does not prove that sub-poll transients are always captured.
