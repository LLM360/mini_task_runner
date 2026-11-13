#!/usr/bin/env python3
"""scrub.py <dir>: replace every HARBOR_SECRET_<NAME> value of /root/.env found in a file under <dir>
with "<NAME removed>", before the record is uploaded. Harbor logs the commands it runs in a
container, environment included, so a secret a seat was given ends up in its trial log; an agent can
also print its own. Symlinks are left alone, as upload.sh never follows them. Prints each file changed.
"""
import os, sys

secrets = {}
for line in open(sys.argv[2] if len(sys.argv) > 2 else "/root/.env"):
    if line.startswith("HARBOR_SECRET_"):
        name, value = line[len("HARBOR_SECRET_"):].rstrip("\n").split("=", 1)
        secrets[value.encode()] = f"<{name} removed>".encode()
for folder, _, names in os.walk(sys.argv[1]):
    for name in names:
        path = os.path.join(folder, name)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        clean = data
        for value, label in secrets.items():
            clean = clean.replace(value, label)
        if clean != data:
            open(path, "wb").write(clean)
            print(path)
