#!/usr/bin/env python3
"""Read-only macOS CPU-time sample for the installed app and USB helper."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, help='Override the selected control app bundle.')
parser.add_argument('--stack', choices=['openduet', 'apogee'], default='openduet')
parser.add_argument('--include-system-audio', action='store_true', help='Report shared audio services separately; not all their work belongs to Duet.')
parser.add_argument('--seconds', type=float, default=10)
parser.add_argument('--label', default='Record visible/hidden state, signal and output settings separately.')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
if not 1 <= args.seconds <= 60: parser.error('Sample duration must be from 1 to 60 seconds.')
app = args.app or Path('/Applications/OpenDuet.app' if args.stack == 'openduet' else '/Applications/Apogee Control 2.app')
if not (app/'Contents/Info.plist').is_file(): raise SystemExit('Selected control app is not installed; no sample taken.')
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
try:
    rows = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True, stderr=subprocess.DEVNULL).splitlines()
except subprocess.CalledProcessError:
    raise SystemExit('Unable to inspect processes in this environment; no sample taken.')
paths = {'app': str(app/'Contents/MacOS'/info['CFBundleExecutable'])}
if args.stack == 'openduet':
    paths['helper'] = str(app/'Contents/MacOS/openduet-identify') + ' --session'
else:
    for role, bundle in [('glue', Path('/Library/Application Support/Apogee/ApogeeGlue/ApogeeGlue.app')),
                         ('messenger', Path('/Library/Application Support/Apogee/ApogeeMessenger/ApogeeMessenger.bundle'))]:
        if (bundle/'Contents/Info.plist').exists():
            executable = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())['CFBundleExecutable']
            paths[role] = str(bundle/'Contents/MacOS'/executable)
pids = {}
for key, path in paths.items():
    matches = [int(row.strip().split(None, 1)[0]) for row in rows if row.strip().split(None, 1)[-1] == path]
    if len(matches) > 1: raise SystemExit('Multiple matching processes; no sample taken.')
    if matches: pids[key] = matches[0]
if not pids: raise SystemExit('No selected control-stack processes are running.')
if args.include_system_audio:
    for service in ['coreaudiod', 'usbaudiod']:
        matches = [int(row.strip().split(None, 1)[0]) for row in rows
                   if Path(row.strip().split(None, 1)[-1].split()[0]).name == service]
        for index, pid in enumerate(matches): pids[service + (f'_{index + 1}' if len(matches) > 1 else '')] = pid
def cpu(pid):
    parts = subprocess.check_output(['ps', '-p', str(pid), '-o', 'time='], text=True).strip().split(':')
    if not parts or not parts[0]: raise SystemExit('Process ended during the sample.')
    return sum(float(value) * 60**index for index, value in enumerate(reversed(parts)))
before = {key: cpu(pid) for key, pid in pids.items()}
start = time.monotonic()
time.sleep(args.seconds)
after = {key: cpu(pid) for key, pid in pids.items()}
elapsed = time.monotonic() - start
version = info.get('CFBundleShortVersionString', 'unknown')
percentages = {key: round(100 * (after[key] - before[key]) / elapsed, 1) for key in pids}
report = {'stack': args.stack, 'version': version, 'duration_seconds': round(elapsed, 2),
          'percent_of_one_core': percentages,
          'control_stack_total_percent': round(sum(value for key, value in percentages.items() if key in paths), 1),
          'control_roles_not_running': sorted(set(paths) - set(pids)),
          'shared_audio_services_note': 'Shared system audio work is not uniquely attributable to this device.' if args.include_system_audio else 'Not sampled',
          'condition': args.label}
text = json.dumps(report, indent=2) + '\n'
print(text, end='')
if args.output: args.output.write_text(text)
