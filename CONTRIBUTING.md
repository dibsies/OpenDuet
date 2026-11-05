# Contributing

OpenDuet currently targets the Duet 2 USB `0c60:0007`. Keep device-specific
protocol evidence separate from related-model assumptions.

- Build with Swift 6 on macOS and run `bash tools/check-release.sh`.
- Keep USB/control and audio state in the shared controller. Views must not
  create another helper, polling loop or USB ownership session.
- Live meter ticks must not invalidate the whole console. Reuse the native
  meter surface and retain hidden-window/unchanged-frame suppression.
- USB acknowledgement means a command transferred, not that analog behavior
  or hardware readback is verified. Preserve unknown-state guards and document
  what was measured versus inferred.
- Never automatically replay phantom power or saved audio settings on launch,
  reconnect or wake. Do not add firmware, security-setting or driver changes
  to ordinary connection flows.
- Include focused regression checks for command ordering, partial failures,
  gain limits, linked offsets and lifecycle behavior when changing them.
- Keep raw reports, recordings, desktop screenshots, reverse-engineering
  binaries, vendor software, credentials and personal paths out of commits.
  Use synthetic screenshots and reviewed, minimal reproduction details.
- Retain attribution for reused code. Describe new protocol evidence without
  committing proprietary implementation artifacts.

For bugs, include app/macOS versions, hardware model and USB VID/PID,
expected/observed behavior, and whether Glue was running. Remove serial
numbers, account names, device UIDs, media titles and personal paths from
any diagnostic excerpt. Do not post an entire system report.

The release checklist distinguishes automated checks from physical audio
validation. Do not mark a hardware test passed solely because its command
returned success.
