#!/usr/bin/env bash
# conductor.sh <trial-dir>: run one trial on this box, upload its record, then power the box off.
# `run` starts it as the systemd service "trial" through ec2/run_script.sh (UNIT=trial).
# <trial-dir> holds spec.json, task/ and runner/ (these scripts) and becomes the record. Steps run
# in order, and a failed step doesn't stop the next (no set -e). Each step's output goes to
# box/steps/<name>.log, and a line {step, start, end, exit} to box/steps/steps.jsonl.
# boxwatch records the machine from the start, before setup. Every model call goes through the
# proxy, on port $PORT of this box, at $PROXY: Docker's default bridge, which is this box too, so
# Harbor's own process and the task's containers both reach it there. Each route in spec.json is named
# after the environment variable a client reads, and the harbor step gets that variable pointing at
# the proxy, as <NAME>=$PROXY/<NAME>. Powers off the machine it runs on.
cd "$1"
mkdir -p box/steps
PORT=8100
PROXY=http://172.17.0.1:$PORT

spec() {  # spec <key>[.<key>]: a field of spec.json, e.g. spec harbor.package
  python3 -c 'import functools, json, sys; print(functools.reduce(lambda v, k: v[k], sys.argv[1].split("."), json.load(open("spec.json"))))' "$1"
}

routes() {  # routes <format>: one line per route in spec.json, with {name} and {url} filled in
  python3 -c 'import json, sys; [print(sys.argv[1].format(name=n, url=u)) for n, u in json.load(open("spec.json"))["routes"].items()]' "$1"
}

with_harbor() {  # with_harbor <command...>: run it with [harbor] args appended and [harbor] env set, each route's variable pointing at the proxy, the HARBOR_SECRET_<NAME>s of /root/.env set as <NAME>, and $VARS in args and env expanded as a shell would
  python3 -c '
import json, os, sys
s = json.load(open("spec.json"))
os.environ.update({name: f"{sys.argv[1]}/{name}" for name in s["routes"]})
os.environ.update(line[len("HARBOR_SECRET_"):].rstrip("\n").split("=", 1) for line in open("/root/.env") if line.startswith("HARBOR_SECRET_"))
os.environ.update({k: os.path.expandvars(str(v)) for k, v in s["harbor"]["env"].items()})
os.execvp(sys.argv[2], sys.argv[2:] + [os.path.expandvars(a) for a in s["harbor"]["args"]])' "$PROXY" "$@"
}

step() {  # step <name> <command...>
  local name=$1 start rc
  shift
  start=$(date -u +%FT%TZ)
  "$@" > "box/steps/$name.log" 2>&1
  rc=$?
  printf '{"step": "%s", "start": "%s", "end": "%s", "exit": %s}\n' "$name" "$start" "$(date -u +%FT%TZ)" "$rc" >> box/steps/steps.jsonl
}

runner/boxwatch.py box > box/steps/boxwatch.log 2>&1 &
boxwatch=$!
step setup runner/setup.sh "$(spec harbor.package)"
[ "$(spec box.kube 2>/dev/null)" != True ] || step kube runner/kube.sh   # only for a Helm-chart task
step tailnet runner/tailnet.sh join "$(spec trial_id)"
runner/proxy.py model_calls "$PORT" $(routes '{name}={url}') > box/steps/proxy.log 2>&1 &
proxy=$!
step harbor with_harbor runner/harbor.sh task harbor
step models curl -sS $(routes "$PROXY/{name}/models")  # what each route's endpoint serves; the proxy records it too
kill "$proxy" "$boxwatch"
wait "$proxy" "$boxwatch" 2>/dev/null   # without this, bash reports each stopped recorder as "Terminated"
step network runner/tailnet.sh ping $(routes '{url}')
step services runner/services.sh services
step scrub runner/scrub.py .   # no HARBOR_SECRETS value may reach the record
step upload runner/upload.sh . "$(spec record)/$(spec trial_id)"
poweroff
