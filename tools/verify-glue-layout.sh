#!/bin/bash
# Check the pinned binary's static transport evidence. Never launches Glue.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s <ApogeeGlue executable>\n' "$0" >&2
    exit 64
fi
binary=$1
expected=a8db9fed76277e251e1c0367aceeb4d004f64b9fbd4a7b86c92e6d8548485b54
actual=$(shasum -a 256 < "$binary")
if [[ ${actual%% *} != "$expected" ]]; then
    printf 'Unsupported ApogeeGlue build. Static addresses require revalidation.\n' >&2
    exit 1
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
xcrun lipo -thin arm64 "$binary" -output "$scratch/glue"
python3 - "$scratch/glue" <<'PY'
import struct
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
slots = (
    (0x2B1378, 0x100036810, "vendor IN"),
    (0x2B1380, 0x100036978, "vendor OUT"),
    (0x2ACBC8, 0x1002ACF00, "Duet II primary type info"),
    (0x2AD490, 0x10000F084, "Duet II input-mode callback"),
    (0x2AD410, 0x10000F218, "Duet II boolean input callback"),
    (0x2ACD00, 0x10000B5F8, "Duet II identifier routine"),
    (0x2B6B20, 0x10016F744, "USB arrival callback"),
)
for offset, expected, name in slots:
    (actual,) = struct.unpack_from("<Q", image, offset)
    if actual != expected:
        raise SystemExit(f"{name}: expected {expected:#x}, found {actual:#x}")
    print(f"{name}: arm64 file offset {offset:#x} -> {actual:#x}")
# Concrete wrapper stores: a5 -> wValue (offset 2), a4 -> wIndex (offset 4).
# The OLED thunk computes inclusive end in w4 and start in w5.
for offset, expected, label in (
    (0x369C0, "e5070079e40b0079", "vendor OUT value/index argument order"),
    (0xBF28, "243d0013453d0013", "OLED end/start argument order"),
):
    actual = image[offset:offset + len(bytes.fromhex(expected))]
    if actual != bytes.fromhex(expected):
        raise SystemExit(f"{label}: pinned arm64 instructions changed")
    print(f"{label}: verified")
factory_table = 0x264E58
factory_base = 0x10016FB58
for pid, expected in ((0x0007, 0x100170510), (0x0016, 0x100170FF4)):
    (entry,) = struct.unpack_from("<H", image, factory_table + 2 * (pid - 7))
    target = factory_base + 4 * entry
    if target != expected:
        raise SystemExit(f"PID {pid:04x}: unexpected factory target {target:#x}")
    print(f"PID {pid:04x}: factory target {target:#x}")

input_modes = struct.unpack_from("<4I", image, 0x2647B0)
if input_modes != (2, 0, 1, 3):
    raise SystemExit(f"Unexpected input mode translation: {input_modes}")
print(f"Input modes (Mic, +4 dBu, -10 dBV, Instrument): {input_modes}")

PY
