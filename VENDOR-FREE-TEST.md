# Vendor coexistence and recovery

OpenDuet uses Apple's native USB audio driver. Its controller needs exclusive
access to the Duet's USB control interface; ApogeeGlue may already own it.
Quitting Control 2 alone does not necessarily stop that background service.
OpenDuet does not uninstall, stop or replace vendor components automatically.

## Before changing an Apogee installation

Keep the vendor installer and a verified backup. Save audio work and turn off
speakers/headphone amplifiers. Do not remove shared Apogee components if you
also use another Apogee interface. Restoring with the vendor installer is an
alternative to the optional developer procedure below.

## Optional reversible developer procedure

This source-only tool is for experienced testers. It can quarantine components
shared by several Apogee products, not just the Duet. Review
`tools/vendor-free-test.py` before use. It validates an explicit allowlist,
refuses executable kext bundles, retains hash-verified copies, and attempts
rollback on a transaction failure. It changes no security settings, firmware
or kernel caches and never restarts the Mac automatically.

Run from a permanent checkout; keep that checkout and its sibling backup
folder in place until restoration is complete. Python 3 is required.

```sh
python3 tools/vendor-free-test.py --prepare
```

This creates verified copies without changing the installation and prints
your unique session path. Save that path privately; do not copy somebody
else's session path or publish its manifest. Inspect it with:

```sh
python3 tools/vendor-free-test.py --status "SESSION_PATH"
```

To stage, release USB and quit OpenDuet, close Control 2, then authenticate
locally in Terminal. Use the exact session path printed by your preparation:

```sh
sudo -v
python3 tools/vendor-free-test.py --stage "SESSION_PATH"
```

Staging stops Glue/Messenger jobs and moves eligible vendor components into
the session's `quarantined` folder. Audio may become unavailable. Save work
and restart before treating this as a clean vendor-free test: cached driver
personalities and running vendor processes may survive staging. Do not
change SIP, startup security or kernel caches to work around a failure.

## Restore the vendor installation

Release USB and quit OpenDuet first. From the same checkout:

```sh
sudo -v
python3 tools/vendor-free-test.py --restore "SESSION_PATH"
```

Restoration verifies copies, refuses to overwrite a replacement installation,
and registers the vendor launch jobs. If it reports a conflict, keep the
backup and review the affected paths rather than deleting files. Restart if
needed, reconnect the Duet and open the vendor application. Retain your
installer as a fallback. Never run OpenDuet and Glue as competing owners.

## Removing OpenDuet

Release USB, quit the app and move it out of Applications. OpenDuet installs
no system service or audio driver. Removing the app does not restore vendor
components quarantined separately; use your own session or vendor installer.
