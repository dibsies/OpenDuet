#!/bin/bash
# Offline regression suite: no USB, audio stream or vendor components are touched.
set -euo pipefail
cd "$(dirname "$0")/.."
for check in command-engine console-sync control-encoders display-events meter-ballistics meter-decoder mixer native-meters physical-controls window-actions system-volume output-safety; do
    bash "tools/verify-$check.sh"
done
for check in duet-identifier privacy-audit vendor-free-test; do
    python3 "tools/verify-$check.py"
done
python3 tools/privacy-audit.py .
git diff --check
printf 'Offline release checks passed. Hardware validation remains separate.\n'
