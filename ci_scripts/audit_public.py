#!/usr/bin/env python3
"""Fail closed; report file names only, never matching secret values."""
import pathlib
import re
import subprocess

files = subprocess.check_output(['git', 'ls-files', '-z']).split(b'\0')
secret = re.compile(rb'BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+')
bad = []
for name in files:
    if not name:
        continue
    path = pathlib.Path(name.decode())
    if path.name == '.env' or path.suffix in {'.p12', '.mobileprovision', '.pem', '.key'}:
        bad.append(str(path))
    elif secret.search(path.read_bytes()):
        bad.append(str(path))
if bad:
    raise SystemExit('Public tree audit failed: ' + ', '.join(bad))
print('Public tree audit passed')
