#!/usr/bin/env bash
# upload.sh <dir> <s3-url>: copy <dir> to <s3-url>, then write upload.json there last. upload.json
# maps every file uploaded to its size in bytes, so its presence means the upload finished.
# Symlinks are never followed: a container can write one into <dir> (Harbor mounts part of it
# inside the task), and it may point anywhere on the box. upload.json lists each with its target.
# Reads how to upload from /root/.env, whichever run put there at launch:
#   AWS keys: a session named after the trial, which can only write this trial's folder.
#   RECORD_POST_*: no key at all, only signed permission to POST files into this trial's folder
#     (see presign.py). Each file is one POST, eight at a time; any that fails fails the upload.
set -euo pipefail
set -a
source /root/.env
set +a
cd "$1"
python3 - <<'PY'
import json, os
paths = sorted(os.path.relpath(os.path.join(d, n)) for d, dirs, files in os.walk(".") for n in files + dirs)
files = {p: os.path.getsize(p) for p in paths if os.path.isfile(p) and not os.path.islink(p)}
links = {p: os.readlink(p) for p in paths if os.path.islink(p)}
json.dump({"files": files, "links": links}, open("/root/upload.json", "w"), indent=1)
PY
if [ -n "${RECORD_POST_URL:-}" ]; then
  post() {  # post <file> <name in the folder>: the signed fields first, since S3 ignores any after the file
    local file=${1//\\/\\\\} fields
    mapfile -t fields < <(python3 -c 'import json, os
for k, v in json.loads(os.environ["RECORD_POST_FIELDS"]).items(): print(f"--form-string\n{k}={v}")')
    curl -fsS -o /dev/null --retry 3 --form-string "key=$RECORD_POST_FOLDER/$2" "${fields[@]}" \
      -F "file=@\"${file//\"/\\\"}\"" "$RECORD_POST_URL" || { echo "upload failed: $2" >&2; return 1; }
  }
  export -f post
  find . -type f -print0 | xargs -0 -P 8 -I{} bash -c 'post "$1" "${1#./}"' _ {}
  post /root/upload.json upload.json
else
  aws s3 cp --recursive --no-follow-symlinks --only-show-errors . "$2"
  aws s3 cp --only-show-errors /root/upload.json "$2/upload.json"
fi
