#!/usr/bin/env bash
# harbor.sh <task-dir> <out-dir> <harbor args...>: run one Harbor trial of <task-dir>. Harbor
# writes its trial folder to exactly <out-dir>, and stops the trial's containers instead of
# deleting them, so services.sh can read them. The harbor args come from the run config; the
# outcome is in <out-dir>/result.json. The trials folder goes to Harbor as an absolute path: docker
# compose cp would resolve a relative one against the task's compose folder.
set -euo pipefail
exec harbor trial start -p "$1" --trials-dir "$(cd "$(dirname "$2")" && pwd)" --trial-name "$(basename "$2")" \
  --environment-kwarg keep_containers=true "${@:3}"
