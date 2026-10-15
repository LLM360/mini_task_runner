#!/usr/bin/env bash
# Print public IPs of RUNNING mini-task-runner boxes, one per line.
#
#   bash ec2/list_fleet.sh            # every running Project=mini-task-runner box
#   bash ec2/list_fleet.sh <fleet>    # only this fleet
#
# Empty output is valid: boxes still booting aren't "running" yet. Poll with
#   until [ -n "$(bash ec2/list_fleet.sh my-fleet)" ]; do sleep 5; done
set -euo pipefail
source "$(dirname "$0")/env.sh"

FILTERS=("Name=tag:Project,Values=mini-task-runner" "Name=instance-state-name,Values=running")
[ -z "${1:-}" ] || FILTERS+=("Name=tag:Fleet,Values=$1")

# [PublicIpAddress] forces one row per IP; awk drops blanks and "None".
aws ec2 describe-instances --filters "${FILTERS[@]}" \
  --query 'Reservations[].Instances[].[PublicIpAddress]' --output text \
  | awk 'NF && $0 != "None"'
