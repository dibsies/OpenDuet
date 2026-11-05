# OpenDuet

A native, dark-mode macOS controller for the **Apogee Duet 2 USB**
(`0c60:0007`). OpenDuet pairs Apple's native USB audio streaming with a
user-space hardware controller. It installs no kernel extensions, background
services or firmware, and uses no Apogee software at runtime.

**0.4.28 beta** — intended for enthusiasts testing this specific device.
It is not yet a verified feature-parity replacement for every Apogee Control 2
function. Other Duet generations are not supported. Tested hardware is Apple
Silicon with macOS 27.2; the build target is macOS 14 or later, but older macOS
versions and Intel Macs have not been validated.

## What is included

- Native console and an optional dark four-channel menu-bar quick mixer.
- Microphone, instrument and line source controls; gain, 48 V, Soft Limit,
  phase and linked input gain.
- Independent main/headphone level, mute, dim, mono and output-source controls.
- macOS volume/mute bridge for Main Out while Duet USB is the system output.
- Direct-monitor mixer controls for inputs and playback, pan, mute and solo.
- Live input/playback meters, peak/clip holds, and calculated post-control
  output meters. Output meters do not measure the analog jacks.
- Host-rendered hardware screen, physical knob and configurable touchpad actions.
- USB reconnect and sleep/wake screen recovery, with explicit setup after
  control state is lost. Saved audio settings and phantom power are never
  automatically replayed.

Earlier native microphone capture, input gain response, main-output listening, hardware
controls/display, and a native 96 kHz duplex stream have been demonstrated.
Final-build DAW recording and detailed routing, mixer, headphone, line-mode and endurance
validation remains incomplete. See [beta scope](BETA-SCOPE.md) and
[hardware evidence](HARDWARE-VALIDATION.md). Original-driver CPU and analog
latency parity have **not** been established; see [performance](PERFORMANCE.md)
and the [comparison procedure](APOGEE-COMPARISON.md).

## Install and first use

Open the DMG and drag OpenDuet to Applications. The local beta is ad-hoc
signed and **not notarized**. No installer or administrator access is needed
for the app itself. Read [installation and recovery](INSTALL-AND-TEST.md)
before changing an existing Apogee installation.

1. Keep speakers and headphone amplifiers off during initial setup.
2. Open OpenDuet and connect USB. If ApogeeGlue owns the device, the app
   reports busy; it does not seize the connection. Closing Control 2 alone
   may not release Glue. Preserve your vendor installer/recovery copies.
3. Choose **Initialize muted** to start at −64 dB/mute using the shown input
   gains, routing/reference and mixer settings. Phantom power stays unchanged;
   enable it only for appropriate connected equipment.
4. The same setup action enables the physical knob at the shown input gains.
   Raise output levels deliberately before listening.

Launch/reconnect can resume the USB lease and hardware screen, but saved
settings are never automatically replayed. Once initialized, control edits
are live: gain, source, 48 V, phase/Soft Limit, output routing/reference,
mono and direct-monitor mixer controls require no Apply buttons. Sample-rate
selection is also immediate and interrupts audio; stop recording/playback first.
Closing or hiding the console does not stop audio. Settings (⌘,) can disable
the menu item. Detailed instructions are in **Help → OpenDuet Guide**, also
available as [GUIDE.md](GUIDE.md). Diagnostics is read-only.

## Build and check

Install the Xcode command-line tools with Swift 6 on macOS. No third-party
package downloads are required.

```sh
swift build
swift run openduet
swift run openduet --discover
bash tools/check-release.sh
```

Discovery is read-only. Review diagnostics before sharing: audio device
names and registry details can identify your setup. The app has no network
client, account, telemetry or automatic uploads.

Package a clean, committed checkout:

```sh
bash tools/package-dmg.sh /absolute/path/OpenDuet-0.4.28-Beta.dmg
```

See [contributing](CONTRIBUTING.md), [release notes](CHANGELOG.md), and the
[release checklist](RELEASE-CHECKLIST.md) and
[validation record](RELEASE-VERIFICATION.md).

## Prior work and licensing

[Duetbar](https://github.com/mulhoon/duetbar) supplies useful Control 2/Glue
protocol research and the MIT meter-scale mapping reused here. Its transport
requires ApogeeGlue; OpenDuet's controller operates directly over USB. Other
related-device projects and the protocol distinctions are documented in
[the prior-art audit](ThirdParty/PRIOR-ART-AUDIT.md) and
[USB protocol evidence](USB-PROTOCOL.md). No proprietary binaries, firmware,
raw captures or vendor installers are distributed.

OpenDuet is [MIT licensed](LICENSE). Incorporated Duetbar code retains its
[upstream MIT notice](ThirdParty/Duetbar-LICENSE.txt). OpenDuet is an independent
community project, not affiliated with or endorsed by Apogee Electronics.
