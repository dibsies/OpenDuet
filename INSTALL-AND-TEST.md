# OpenDuet 0.4.28 beta — installation and testing

This beta targets Duet 2 USB (`0c60:0007`). Native USB audio handles recording
and playback; OpenDuet handles controls and the screen. It installs no driver,
service or firmware. The tested setup is Apple Silicon/macOS 27.2; macOS 14
is the build target, with other hardware/system versions unvalidated.

## Install

Quit the previous OpenDuet app, open the DMG and drag OpenDuet to Applications.
The local beta is ad-hoc signed and not notarized. Do not change system
security settings to install it. The app itself needs no administrator password.
Preserve your Apogee installer and recovery copies before changing that stack.

If ApogeeGlue owns USB, OpenDuet reports busy instead of seizing it. Closing
Control 2 alone may not release Glue. The separate reversible developer
procedure is in VENDOR-FREE-TEST.md; it is not run by the app.

## First use

1. Keep speakers/headphone amplifiers off during initial setup.
2. Connect USB, review the shown input gains, and choose **Initialize muted**.
   Outputs start muted at −64 dB. Setup uses the shown gains, routing/reference
   and mixer settings and enables the knob. **Phantom power is unchanged.**
3. Set output levels deliberately, then unmute as appropriate.

Normal edits apply live: input source/gain/48 V/Soft Limit/phase; main and
headphone level/mute/dim/mono/routing; line reference; and direct-monitor mixer.
Sample-rate selection also applies immediately and interrupts audio—stop
recording/playback before changing it. Detailed instructions and validation
limits are under **Help → OpenDuet Guide**, bundled from GUIDE.md.

## Keyboard, windows and recovery

Settings → **Keyboard volume controls Main Out** enables fixed 2 dB normal
keyboard steps and mute only while Duet USB is the default output and Main Out
is initialized. The native HUD follows known output state. Other OS master-
volume adjustments are relative too; use the app dial for exact absolute dB.
Headphones and inputs stay independent. No global key interception or input
permissions are required.

Hide Mixer dismisses only the full console. The menu icon opens the quick
mixer independently; Show Mixer restores the console. Closing a window does
not quit the shared controller. Settings can disable the menu item; Quit lives
in More actions and the standard application menu.

Wake/reconnect restores the connection and screen without replaying saved
settings or phantom. If state was lost, **Initialize muted** reestablishes it
and enables the knob in the same action. Release USB cancels retries.

Diagnostics is read-only. Review device names/paths before sharing its output.
Read RELEASE-VERIFICATION.md and BETA-SCOPE.md for remaining hardware tests;
full feature parity, original-driver performance parity and endurance are
not certified. Release USB and quit before restoring any vendor services.
Use the recovery command from your own verified backup session; see
[VENDOR-FREE-TEST.md](VENDOR-FREE-TEST.md) for preparation, restoration and
removing OpenDuet. Never use a session path copied from another machine.

## Verify or build

```sh
shasum -a 256 -c OpenDuet-0.4.28-Beta.dmg.sha256
swift build
bash tools/check-release.sh
bash tools/package-dmg.sh /absolute/path/OpenDuet-0.4.28-Beta.dmg
```

The offline suite touches no USB device or audio stream. The separate native
stream test starts silent audio and changes/restores sample rate; run it only
deliberately with other audio work stopped. The package contains matching
source, MIT and third-party notices, guide, release notes and validation scope.
