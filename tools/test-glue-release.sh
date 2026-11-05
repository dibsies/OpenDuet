#!/bin/bash
# Run from an interactive Terminal during an audio maintenance window.
set -euo pipefail
tool_dir=$(cd "$(dirname "$0")" && pwd)
reconnect=0
audio_check=0
capture_check=0
control_reads=0
mode_roundtrip=0
screen_check=0
case "$#" in
    0) ;;
    1)
        [[ -t 0 ]] || exit 64
        case "$1" in
            --reconnect) reconnect=1 ;;
            --capture-check) capture_check=1; audio_check=1 ;;
            *) exit 64 ;;
        esac
        ;;
    2)
        [[ $1 == --reconnect && -t 0 ]] || exit 64
        reconnect=1
        case "$2" in
            --audio-check) audio_check=1 ;;
            --screen-check) screen_check=1; audio_check=1 ;;
            --control-readback) control_reads=1 ;;
            --mode-roundtrip) control_reads=1; mode_roundtrip=1 ;;
            *) exit 64 ;;
        esac
        ;;
    *) exit 64 ;;
esac
if [[ $control_reads == 1 ]]; then
    log="$tool_dir/../../OpenDuet-control-readback.log"
    exec > >(tee "$log") 2>&1
    printf 'OpenDuet control readback · %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Results log: %s\n' "$log"
fi
scratch=$(mktemp -d)
service=system/com.apogeedigital.apogeeglue
plist=/Library/LaunchDaemons/com.apogeedigital.apogeeglue.plist
restore=0
restore_input_mode=

duet_owner() {
    /usr/sbin/ioreg -p IOUSB -l -w0 | awk '
        /<class IOUSBHostDevice,/ { duet = ($0 ~ /Duet USB@/) }
        duet && /"UsbExclusiveOwner"/ { print; duet = 0 }
    '
}

wait_for_release() {
    local attempt owner
    for ((attempt = 0; attempt < 40; attempt++)); do
        owner=$(duet_owner)
        if [[ -z $owner ]] && ! sudo -n launchctl print "$service" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    printf 'Glue did not release the Duet within 10 seconds. Probe skipped.\n' >&2
    return 1
}

restore_glue() {
    local attempt owner
    if ! sudo -n -v >/dev/null 2>&1; then
        printf 'Administrator authorization expired. Enter your password locally to restore Glue.\n' >&2
        sudo -v || return 1
    fi
    for ((attempt = 0; attempt < 40; attempt++)); do
        if sudo -n launchctl print "$service" >/dev/null 2>&1; then
            owner=$(duet_owner)
            if [[ $owner == *ApogeeGlue* ]]; then
                printf 'Restored ownership: %s\n' "$owner"
                return 0
            fi
        else
            sudo -n launchctl bootstrap system "$plist" || return 1
        fi
        sleep 0.25
    done
    printf 'Could not verify that Glue reclaimed the Duet. Check Control 2 before using audio.\n' >&2
    return 1
}

cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n $restore_input_mode ]]; then
        printf 'Restoring Input 2 mode to %s before restarting Glue…\n' "$restore_input_mode"
        "$scratch/probe" --experimental-mode 2 "$restore_input_mode" --apply || result=1
    fi
    if [[ $restore == 1 ]]; then
        restore_glue || result=1
    fi
    rm -rf "$scratch"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

clang "$tool_dir/../Sources/DuetIdentifier/"*.c -framework IOKit -framework CoreFoundation -o "$scratch/probe"
if [[ $screen_check == 1 ]]; then
    cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
var snapshot = DeviceDisplayRenderer.Snapshot()
snapshot.outputs[0] = .init(level: -64, muted: true)
snapshot.outputs[1] = .init(level: -64, muted: true)
guard let pixels = DeviceDisplayRenderer.render(snapshot) else { exit(1) }
try Data(pixels).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
    swiftc -module-cache-path "$tool_dir/../.build/clang-cache" "$tool_dir/../Sources/OpenDuet/DeviceDisplayRenderer.swift" "$tool_dir/../Sources/OpenDuet/DuetbarMeterScale.swift" "$scratch/main.swift" -o "$scratch/render"
    "$scratch/render" "$scratch/screen.rgb565"
fi
sudo -v
sudo -n launchctl print "$service" >/dev/null
test -r "$plist"
restore=1
sudo -n launchctl bootout "$service"
wait_for_release
if [[ $reconnect == 1 ]]; then
    printf 'Unplug and reconnect the Duet USB cable, then press Return. Ctrl-C restores Glue.\n'
    IFS= read -r
fi
printf 'Waiting five seconds after USB ownership clears…\n'
sleep 5
if [[ $capture_check == 0 ]] && ! "$scratch/probe"; then
    printf 'First probe failed. Waiting another five seconds before one retry…\n'
    sleep 5
    "$scratch/probe"
fi
if [[ $control_reads == 1 ]]; then
    printf 'Reading input modes (no settings writes)…\n'
    modes=$("$scratch/probe" --input-modes)
    printf '%s\n' "$modes"
    if [[ $mode_roundtrip == 1 ]]; then
        original_one=$(printf '%s\n' "$modes" | awk '/^INPUT_MODES / {print $2}')
        original_two=$(printf '%s\n' "$modes" | awk '/^INPUT_MODES / {print $3}')
        [[ $original_one =~ ^[0-3]$ && $original_two =~ ^[0-3]$ ]] || exit 1
        restore_input_mode=$original_two
        test_mode=3
        [[ $original_two != 3 ]] || test_mode=2
        printf 'Testing Input 2 mode %s → %s → %s…\n' "$original_two" "$test_mode" "$original_two"
        "$scratch/probe" --experimental-mode 2 "$test_mode" --apply
        changed=$("$scratch/probe" --input-modes)
        printf '%s\n' "$changed"
        printf '%s\n' "$changed" | awk -v one="$original_one" -v two="$test_mode" '
            /^INPUT_MODES / { if ($2 == one && $3 == two) good=1 }
            END { exit !good }'
        "$scratch/probe" --experimental-mode 2 "$original_two" --apply
        restored=$("$scratch/probe" --input-modes)
        printf '%s\n' "$restored"
        printf '%s\n' "$restored" | awk -v one="$original_one" -v two="$original_two" '
            /^INPUT_MODES / { if ($2 == one && $3 == two) good=1 }
            END { exit !good }'
        restore_input_mode=
        printf 'PASS: Input 2 mode changed and original mode read back successfully.\n'
    fi
    printf 'Reading raw meters (no settings writes)…\n'
    "$scratch/probe" --meters
fi
if [[ $screen_check == 1 ]]; then
    printf 'Applying the approved muted startup, then the original OpenDuet screen…\n'
    "$scratch/probe" --experimental-startup-muted device 1 --apply
    "$scratch/probe" --experimental-display device "$scratch/screen.rgb565" --apply
    printf 'Screen transfers finished. Check the Duet display; inputs show unknown, outputs show muted at -64 dB.\n'
fi
if [[ $audio_check == 1 ]]; then
    printf 'Audio test window ready. Leave USB connected. Leave Terminal waiting. Press Return when done to restore Glue. Ctrl-C also restores Glue.\n'
    IFS= read -r
fi
