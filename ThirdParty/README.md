# Duetbar source review and reuse

See [the broader prior-art audit](PRIOR-ART-AUDIT.md) for pinned direct USB
implementations, device-specific command differences and the reuse decision.

Reviewed upstream revision 463c35f0881dfb5e40270867a1e946db6ad463bd,
https://github.com/mulhoon/duetbar .

Duetbar's existing GlueClient, state parser and meter decoder served as
the live vendor-backed reference in this project. Reuse those for
reference checks. OpenDuet's shipping backend must operate without Glue.

The first incorporated component is MeterScale from DuetbarApp.swift.
The MIT notice is retained in Duetbar-LICENSE.txt and packaged in the app.
Its nonlinear dB mapping now drives OpenDuet's raw meter bars.

Further reuse candidates are the dial UI, channel card presentation,
input source labels/ranges and global hotkey handling. Preserve upstream
copyright notices with incorporated code. Transport-dependent model
actions must be adapted to the direct backend and checked for state
confirmation. Duetbar performs some optimistic UI updates, which do not
prove a direct USB write succeeded.

Do not port the localhost property IDs to USB requests. They identify
Glue properties, not device commands. Do not use Duetbar's 20-group
meter map for the raw USB ten-lane packet. The two formats differ.

Duetbar provides input modes/gain/48 V/Soft Limit/phase, output
gain/mute/dim/mono/reference, sample rate, live Glue meters, and shortcuts.
Its published source does not implement a replacement for Glue, hardware
mixer editing, output source editing or touchpad assignment. OpenDuet's
remaining protocol work targets those gaps and independent operation.

## Menu-bar interaction reference

Duetbar's pinned DuetbarApp uses SwiftUI MenuBarExtra with window-style
popover content and a single application-owned model. OpenDuet follows
that public interaction pattern with original quick-output controls and
show/hide actions for its existing console. No Glue transport or additional
Duetbar code is incorporated for this feature; the existing MIT meter-scale
attribution remains intact. Both OpenDuet surfaces share one ConsoleModel,
USB lease and meter pipeline.
