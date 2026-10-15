#!/usr/bin/env bash
# Terminate ONE box by public IP. Only Project=mini-task-runner instances are ever
# matched, so a stray IP is a no-op. The root volume goes with it
# (DeleteOnTermination, set by create_one.sh). Does not wait.
#
#   bash ec2/terminate_one.sh <ip>
#
# Stdout: the terminated instance ID; nothing when the IP isn't ours.
set -euo pipefail
source "$(dirname "$0")/env.sh"

IP="${1:?usage: terminate_one.sh <ip>}"

IDS=$(aws ec2 describe-instances \
  --filters "Name=ip-address,Values=$IP" "Name=tag:Project,Values=mini-task-runner" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
# shellcheck disable=SC2086  # deliberate: word-split into $1..$n (bash 3.2 has no mapfile)
set -- $IDS

case $# in
  0) echo "not found: $IP" >&2 ;;
  1) aws ec2 terminate-instances --instance-ids "$1" >/dev/null && echo "$1" ;;
  *) echo "ambiguous: $IP matches $# mini-task-runner instances ($*)" >&2; exit 1 ;;
esac
