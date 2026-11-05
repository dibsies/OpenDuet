#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import zipfile
spec = importlib.util.spec_from_file_location('privacy_audit', Path(__file__).with_name('privacy-audit.py'))
audit = importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
terms = {b'private-example-identity'}
assert not audit.scan_data('clean', b'OpenDuet Contributors <contributors@example.invalid>', terms)
assert audit.scan_data('identity', b'PRIVATE-EXAMPLE-IDENTITY', terms)
assert audit.scan_data('home', b'/' + b'Users' + b'/example-user/project/file.swift', terms)
assert audit.scan_data('key', b'-----BEGIN ' + b'PRIVATE KEY-----', terms)
assert audit.scan_data('token', b'ghp_' + b'x' * 30, terms)
assert audit.scan_data('fine-grained token', b'github_pat_' + b'x' * 40, terms)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root/'source.swift').write_text('let gain = 24\n')
    assert not audit.scan_path(root, terms)
    with zipfile.ZipFile(root/'source.zip', 'w') as archive:
        archive.writestr('report.txt', 'private-example-identity')
    assert audit.scan_path(root, terms)
    (root/'source.zip').unlink()
    (root/'private-link').symlink_to(root/'source.swift')
    assert audit.scan_path(root, terms)
print('Privacy identity/path/key/token/archive/symlink fixtures passed')
