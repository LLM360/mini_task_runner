#!/usr/bin/env bash
# Dummy workload for testing run_script.sh: prints box facts, the args it got
# (one per line, so quoting is visible), HELLO_VAR from /root/.env if pushed
# with ENV_FILE, and exits 3 when the first arg is "fail".
#
#   bash ec2/run_script.sh <ip> ec2/examples/hello.sh "two words" x
#   ENV_FILE=ec2/examples/hello.vars bash ec2/run_script.sh <ip> ec2/examples/hello.sh
#   bash ec2/run_script.sh <ip> ec2/examples/hello.sh fail; echo "exit=$?"
set -euo pipefail
. /etc/os-release
echo "host=$(hostname) user=$(whoami) os=\"$PRETTY_NAME\" arch=$(uname -m)"
echo "vcpu=$(nproc) mem=$(free -g | awk '/Mem:/{print $2}')G disk=$(df -h / | awk 'NR==2{print $2}')"
echo "args ($#):"
for a in "$@"; do echo "  [$a]"; done
if [ -f /root/.env ]; then
  set -a; . /root/.env; set +a
  echo "/root/.env: present, mode $(stat -c %a /root/.env), HELLO_VAR=${HELLO_VAR:-<unset>}"
else
  echo "/root/.env: absent"
fi
[ "${1:-}" != fail ] || { echo "failing on purpose with exit 3" >&2; exit 3; }
