# Existing implementation audit

Reviewed 2026-11-03. Scope: an independent replacement for Apogee Control 2
for USB VID:PID **0c60:0007**, on Apple Silicon macOS. Repository searches
cannot prove that no other implementation exists. No complete replacement
meeting this scope was located in this review.

## Sources inspected

| Project | Pinned source / scope | Use in OpenDuet |
|---|---|---|
| [Duetbar](https://github.com/mulhoon/duetbar) | `463c35f0881dfb5e40270867a1e946db6ad463bd`, MIT, native macOS UI using ApogeeGlue TCP | Reuse licensed meter presentation already incorporated; consult UI, state schema, gain ranges and active-mode behavior. Its transport requires the vendor daemon. |
| [take_control](https://github.com/stefanocoding/take_control) | `fad3608899dc7b21a0d2e229724d34371563bf88`, GPL-3.0, Python/PyUSB/wx, PID **0016** | Existing direct USB implementation is a protocol reference. Do not assume its model-specific commands or indices apply to 0007. No source copied into the shipping app in this audit. |
| [duet2-startup](https://github.com/matt8707/duet2-startup) | `42586b11489103b367a1d285918eb84dd2da55fb`, MIT, macOS Python/PyUSB, PID **0007** | Actual executable path writes input mode to both inputs and reads it back. Corroborates the four mode values and vendor transfer format. The larger command dictionary is inherited reference data, not evidence that every listed command works on 0007. |
| [apogee-one2-linux](https://github.com/stevebrodie/apogee-one2-linux) | `5ca447a31412b5f1d0dc5a72226656dfbb4ad65d`, ONEv2 PID **0017**, Linux patches, USB captures and keepalive script | Reference for initialization/status investigations. Its 0x29 read is six bytes, versus 29 in the independently traced Duet II handler. Do not transplant initialization or watchdog assumptions across devices. Upstream reports stable playback remains unconfirmed. |
| [ASFireWire](https://github.com/mrmidi/ASFireWire) | Public README reviewed; DriverKit FireWire stack | Relevant to the original FireWire Duet, a different transport. Does not replace the USB Duet II control backend. |

The first three projects were already linked in OpenDuet's README before
this audit. This review pins and inspects their executable implementations
and adds related-device and modern DriverKit work to the comparison.
Reference implementations were reviewed as source and were not executed
against hardware during this audit.

## Concrete compatibility checks

All values below are hexadecimal. The Duet II column comes from the
model-specific vendor handler documented in [USB-PROTOCOL.md](../USB-PROTOCOL.md).

| Control | take_control, PID 0016 | Traced Duet II, PID 0007 | Decision |
|---|---|---|---|
| Input mode | request 16, index 0/1, values 0/1/2/3 | Same; also exercised by duet2-startup | Reuse established mode vocabulary and encoding. |
| Phantom / Soft Limit / phase | requests 15 / 11 / 13, index 0/1 | Same request family and indices | Existing public corroboration; hardware behavior still needs testing. |
| Mic / instrument gain | requests 34 / 3e, index 0/1 | Same requests, **index 1/2** | Preserve Duet II indices. |
| Output level | request 33, index 0/1 | request 33, **paired indices 1/2 or 3/4** | Preserve paired writes. |
| Mono | request 46, separate output index | request **38**, packed main/headphone bits | Do not port 0016 command. |
| Output source | request 53, separate output index | request **37**, packed selectors | Resolve Duet II selector labels independently. |
| Line reference | request b6 | request **18**, both main channels | Do not port 0016 command. |
| Mixer | requests 4c–4f for individual properties | host computes coefficients; request **10**, eight-byte left/right banks | Reuse mixer concepts; implement the confirmed Duet II coefficient transport. |

## Development decision

Continue with Apple's native USB audio streaming and a direct user-space
Duet II control backend. Reuse Duetbar's compatible MIT components with
attribution. Use take_control and duet2-startup to avoid rediscovering
established controls, with the model checks above. Concentrate remaining
reverse engineering on independent startup/state synchronization, hardware
events, touchpad assignment, route labels, and mixer integration.

Do not build a custom audio driver unless native streaming tests reveal
a concrete limitation. Do not treat a successful USB write, a related
device's working command, or a GUI's optimistic state as full validation.
This audit changed no installed drivers, services or device settings.
