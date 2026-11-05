#!/usr/bin/env python3
"""Reversible vendor-component quarantine. Default/status never changes installation.
No reboot, kernel-cache rebuild, security change or firmware operation is performed.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile

EXTENSIONS = ["DuetUSBOverideDriver.kext", "Duet3Override.kext", "QuartetUSBOverideDriver.kext", "ONEv2USBOverideDriver.kext", "BoomOverride.kext", "SDOverride.kext"]
SERVICES = ["com.apogeedigital.apogeeglue", "com.apogeedigital.apogeemessenger"]
ALLOWED = [Path('/Library/Extensions') / name for name in EXTENSIONS] + [Path('/Library/LaunchDaemons') / (name + '.plist') for name in SERVICES] + [
    Path('/Applications/Apogee Control 2.app'),
    Path('/Library/Application Support/Apogee/ApogeeGlue/ApogeeGlue.app'),
    Path('/Library/Application Support/Apogee/ApogeeMessenger/ApogeeMessenger.bundle')]
BASE = Path(__file__).resolve().parents[2] / 'OpenDuet-vendor-backups'

def digest(path):
    path = Path(path)
    h = hashlib.sha256()
    entries = [path] if not path.is_dir() else [path] + sorted(path.rglob('*'))
    for entry in entries:
        relative = '.' if entry == path else str(entry.relative_to(path))
        h.update(relative.encode() + b'\0')
        if entry.is_symlink(): h.update(b'link\0' + os.readlink(entry).encode())
        elif entry.is_file():
            h.update(b'file\0')
            with entry.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''): h.update(block)
        else: h.update(b'directory\0')
    return h.hexdigest()

def command(args, check=True):
    return subprocess.run(args, check=check)

def service_loaded(name):
    return subprocess.run(['/bin/launchctl', 'print', 'system/' + name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def write_manifest(session, manifest):
    temporary = session / 'manifest.tmp'
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(session / 'manifest.json')

def prepare():
    BASE.mkdir(parents=True, exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix='session-', dir=BASE))
    (session / 'copies').mkdir(); (session / 'quarantined').mkdir()
    items = []
    for source in ALLOWED:
        if not source.exists(): continue
        if source.is_symlink(): raise RuntimeError('Refusing linked component: ' + str(source))
        if source.suffix == '.kext':
            info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
            if info.get('CFBundleExecutable') or 'apogee' not in info.get('CFBundleIdentifier', '').lower():
                raise RuntimeError('Unexpected executable/vendor in ' + str(source))
        before = digest(source)
        copy = session / 'copies' / source.name
        command(['/usr/bin/ditto', str(source), str(copy)])
        if digest(copy) != before or digest(source) != before:
            raise RuntimeError('Backup verification failed: ' + str(source))
        st = source.stat()
        items.append({'source': str(source), 'sha256': before, 'uid': st.st_uid, 'gid': st.st_gid, 'mode': st.st_mode & 0o7777})
    manifest = {'version': 1, 'prepared_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'state': 'prepared', 'items': items}
    write_manifest(session, manifest)
    print(f'Verified copies of {len(items)} components. Installation unchanged.\n{session}')

def load(session):
    session = Path(session).resolve()
    if session.parent != BASE.resolve() or session.is_symlink(): raise RuntimeError('Session must be inside the project backup directory')
    manifest = json.loads((session / 'manifest.json').read_text())
    if manifest.get('version') != 1: raise RuntimeError('Unsupported manifest')
    sources = [Path(item['source']) for item in manifest['items']]
    if len(set(sources)) != len(sources) or any(source not in ALLOWED for source in sources): raise RuntimeError('Unexpected component path')
    for folder in ['copies', 'quarantined']:
        if (session / folder).is_symlink(): raise RuntimeError('Refusing linked backup folder')
    return session, manifest

def move_items(items, session, move):
    # Validate the whole transaction before its first mutation.
    for item in items:
        source = Path(item['source']); target = session / 'quarantined' / source.name
        if target.exists() or not source.exists() or source.is_symlink(): raise RuntimeError('Component state changed: ' + str(source))
        if digest(source) != item['sha256'] or digest(session / 'copies' / source.name) != item['sha256']:
            raise RuntimeError('Component/backup hash changed: ' + str(source))
    moved = []
    try:
        for item in items:
            source = Path(item['source']); target = session / 'quarantined' / source.name
            # Include the current pair before calling move so interruption after rename is recoverable.
            moved.append((source, target)); move(source, target)
    except BaseException as original:
        errors = []
        for source, target in reversed(moved):
            if target.exists() and not source.exists():
                try: move(target, source)
                except BaseException as error: errors.append(str(error))
        if errors: raise RuntimeError('Rollback incomplete: ' + '; '.join(errors)) from original
        raise

def restore_items(items, session, move):
    errors = []
    for item in reversed(items):
        source = Path(item['source']); target = session / 'quarantined' / source.name
        try:
            if target.exists():
                if source.exists(): raise RuntimeError('Refusing to overwrite a new installation: ' + str(source))
                if digest(target) != item['sha256']: raise RuntimeError('Quarantined component changed: ' + str(target))
                move(target, source)
            elif not source.exists(): raise RuntimeError('Component missing; use the verified copy or vendor installer: ' + str(source))
        except Exception as error: errors.append(str(error))
    if errors: raise RuntimeError('Restoration incomplete: ' + '; '.join(errors))

def authorize():
    if not sys.stdin.isatty(): raise RuntimeError('Run this step in interactive Terminal; enter the administrator password locally')
    command(['/usr/bin/sudo', '-v'])

def privileged_move(source, target):
    command(['/usr/bin/sudo', '-n', '/bin/mv', str(source), str(target)])

def stage(session, manifest):
    processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if any('bash ' in line and 'test-glue-release.sh' in line for line in processes.splitlines()):
        raise RuntimeError('Finish the older test runner first: Release USB in OpenDuet, then press Return in its Terminal window')
    if any(line.startswith('/Applications/Apogee Control 2.app/Contents/MacOS/') for line in processes.splitlines()):
        raise RuntimeError('Close Apogee Control 2 before staging')
    registry = subprocess.check_output(['/usr/sbin/ioreg', '-p', 'IOUSB', '-l', '-w0'], text=True)
    if any('UsbExclusiveOwner' in line and ('openduet' in line.lower() or 'OpenDuet' in line) for line in registry.splitlines()):
        raise RuntimeError('Release USB in OpenDuet before staging')
    # move_items repeats this check after services stop; perform it before authorization too.
    for item in manifest['items']:
        source = Path(item['source'])
        if not source.exists() or digest(source) != item['sha256'] or digest(session / 'copies' / source.name) != item['sha256']:
            raise RuntimeError('Component or backup changed: ' + str(source))
    authorize()
    manifest['services_loaded'] = {name: service_loaded(name) for name in SERVICES}
    write_manifest(session, manifest)
    try:
        for name, loaded in manifest['services_loaded'].items():
            if loaded: command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'bootout', 'system/' + name])
        move_items(manifest['items'], session, privileged_move)
    except BaseException:
        restore_items(manifest['items'], session, privileged_move)
        for name, loaded in manifest['services_loaded'].items():
            if loaded and not service_loaded(name): command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'bootstrap', 'system', '/Library/LaunchDaemons/' + name + '.plist'])
        raise
    manifest['state'] = 'quarantined'; write_manifest(session, manifest)
    print('Components quarantined with verified copies retained. No cache/security/firmware changes made.')
    print('Save work and arrange a restart before calling this a clean test. Cached personalities and Messenger may remain active until restart.')
    print('Recovery: python3 ' + str(Path(__file__).resolve()) + ' --restore ' + str(session))

def restore(session, manifest):
    authorize(); restore_items(manifest['items'], session, privileged_move)
    # Explicit recovery restores the normal installation, including RunAtLoad jobs.
    # Failure rollback above separately preserves the pre-test loaded-job state.
    for name in SERVICES:
        plist = '/Library/LaunchDaemons/' + name + '.plist'
        if Path(plist).exists() and not service_loaded(name):
            command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'bootstrap', 'system', plist])
    manifest['state'] = 'restored'; write_manifest(session, manifest)
    print('Original components restored. Release USB in OpenDuet so Glue can reclaim it; restart may be needed for cached personalities.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--prepare', action='store_true'); modes.add_argument('--status', type=Path)
    modes.add_argument('--stage', type=Path); modes.add_argument('--restore', type=Path)
    args = parser.parse_args()
    if args.prepare: prepare(); return
    session, manifest = load(args.status or args.stage or args.restore)
    if args.status:
        print('State:', manifest['state'])
        for item in manifest['items']:
            source = Path(item['source']); print(source.name, 'installed' if source.exists() else 'absent', 'quarantined' if (session / 'quarantined' / source.name).exists() else '', 'copy verified' if digest(session / 'copies' / source.name) == item['sha256'] else 'COPY CHANGED')
    elif args.stage: stage(session, manifest)
    else: restore(session, manifest)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try: main()
    except (Exception, KeyboardInterrupt) as error:
        print('Vendor-free test stopped:', error, file=sys.stderr); sys.exit(1)
