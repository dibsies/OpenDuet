#!/usr/bin/env python3
"""Read-only pre-publication checks. Reports categories/relative names, never matched secrets."""
import argparse
import os
from pathlib import Path
import pwd
import re
import socket
import subprocess
import sys
import zipfile

NEUTRAL_NAME = 'OpenDuet Contributors'
NEUTRAL_EMAIL = 'contributors@example.invalid'
SKIP = {'.git', '.build', '.swiftpm', '__pycache__'}
PATTERNS = {
    'absolute home path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    'private key': re.compile(rb'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----'),
    'credential token': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{30,})'),
}

def private_terms(repo):
    terms = {Path.home().name, socket.gethostname()}
    terms.add(pwd.getpwuid(os.getuid()).pw_gecos.split(',')[0])
    history = subprocess.run(['git', '-C', str(repo), 'log', '--all', '--format=%an%x00%ae%x00%cn%x00%ce'], capture_output=True, text=True)
    if history.returncode == 0:
        terms.update(history.stdout.replace('\n', '\0').split('\0'))
    public_aliases = {NEUTRAL_NAME.casefold(), NEUTRAL_EMAIL.casefold(), 'openduet', 'openduet contributor'}
    return {term.casefold().encode() for term in terms if len(term) >= 5 and term.casefold() not in public_aliases}

def scan_data(label, data, terms):
    findings = [(label, category) for category, pattern in PATTERNS.items() if pattern.search(data)]
    folded = data.lower()
    if any(term in folded for term in terms): findings.append((label, 'private identity term'))
    return findings

def scan_path(path, terms):
    findings = []
    files = [path] if path.is_file() else sorted(path.rglob('*'))
    for file in files:
        relative = file.name if path.is_file() else file.relative_to(path).as_posix()
        if any(part in SKIP for part in Path(relative).parts): continue
        if file.is_symlink():
            findings.append((relative, 'symlink requires review')); continue
        if not file.is_file(): continue
        findings.extend(scan_data(relative + ' [filename]', relative.encode(), terms))
        if file.suffix.lower() in {'.key', '.pem', '.p12', '.pfx', '.bundle'}:
            findings.append((relative, 'private artifact requires review'))
        if zipfile.is_zipfile(file):
            with zipfile.ZipFile(file) as archive:
                for entry in archive.infolist():
                    label = relative + ':' + entry.filename
                    if entry.is_dir(): continue
                    if entry.file_size > 64 * 1024 * 1024:
                        findings.append((label, 'oversize archive member requires review')); continue
                    findings.extend(scan_data(label + ' [filename]', entry.filename.encode(), terms))
                    findings.extend(scan_data(label, archive.read(entry), terms))
        else:
            findings.extend(scan_data(relative, file.read_bytes(), terms))
    return findings

def history_is_neutral(repo):
    result = subprocess.run(['git', '-C', str(repo), 'log', '--all', '--format=%an%x00%ae%x00%cn%x00%ce'], capture_output=True, text=True)
    expected = '\0'.join([NEUTRAL_NAME, NEUTRAL_EMAIL, NEUTRAL_NAME, NEUTRAL_EMAIL])
    return result.returncode == 0 and bool(result.stdout.strip()) and all(line == expected for line in result.stdout.splitlines())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', type=Path, nargs='+')
    parser.add_argument('--identity-repo', type=Path, default=Path.cwd())
    parser.add_argument('--require-neutral-history', action='store_true')
    args = parser.parse_args()
    terms = private_terms(args.identity_repo)
    findings = []
    for path in args.paths:
        if not path.exists(): findings.append((path.name, 'missing artifact')); continue
        findings.extend(scan_path(path, terms))
    if args.require_neutral_history and not history_is_neutral(args.identity_repo):
        findings.append(('Git history', 'non-neutral authorship; do not publish this history'))
    for label, category in findings: print(f'REVIEW: {label}: {category}')
    if findings: return 1
    print('Privacy pattern checks passed; manual review of screenshots, diagnostics and account/profile is still required.')
    return 0

if __name__ == '__main__': sys.exit(main())
