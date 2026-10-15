#!/usr/bin/env bash
# upload.sh <dir> <s3-url>: copy <dir> to <s3-url>, then write upload.json there last. upload.json
# maps every file uploaded to its size in bytes, so its presence means the upload finished.
# Symlinks are never followed: a container can write one into <dir> (Harbor mounts part of it
# inside the task), and it may point anywhere on the box. upload.json lists each with its target.
# Reads its AWS keys from /root/.env: a session of the bucket's role that run took on at launch,
# named after the trial, which can only write this trial's folder.
set -euo pipefail
set -a
source /root/.env
set +a
cd "$1"
aws s3 cp --recursive --no-follow-symlinks --only-show-errors . "$2"
python3 - <<'EOF'
import json, os
paths = sorted(os.path.relpath(os.path.join(d, n)) for d, dirs, files in os.walk(".") for n in files + dirs)
files = {p: os.path.getsize(p) for p in paths if os.path.isfile(p) and not os.path.islink(p)}
links = {p: os.readlink(p) for p in paths if os.path.islink(p)}
json.dump({"files": files, "links": links}, open("upload.json", "w"), indent=1)
EOF
aws s3 cp --only-show-errors upload.json "$2/upload.json"
