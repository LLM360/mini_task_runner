#!/usr/bin/env bash
# Run a local script on a box as root: wait for root SSH, copy the script to
# /root/, run it with the given args, stream its output, exit with its code.
#
#   bash ec2/run_script.sh <ip> <script> [args...]
#   ENV_FILE=.env bash ec2/run_script.sh <ip> <script> [args...]
#   DIR=my_job UNIT=job bash ec2/run_script.sh <ip> my_job/main.sh /root/my_job
#
# ENV_FILE (optional): copied to /root/.env (mode 0600) over stdin first, so
# secrets never appear in a command line. Scripts source it if they need it.
# DIR (optional): a local folder copied to /root/<its name> first, keeping
# modes and symlinks, for scripts that need more than one file.
# UNIT (optional): run the script as the systemd service <UNIT> instead, and
# exit 0 as soon as it has started; it keeps running without SSH. Watch it with
#   ssh "${SSH_OPTS[@]}" root@<ip> journalctl -fu <UNIT>
set -euo pipefail
source "$(dirname "$0")/env.sh"

IP="${1:?usage: run_script.sh <ip> <script> [args...]}"
SCRIPT="${2:?usage: run_script.sh <ip> <script> [args...]}"
shift 2
[ -f "$SCRIPT" ] || { echo "script not found: $SCRIPT" >&2; exit 1; }

# A box reports "running" before sshd is up and cloud-init has authorized root.
DEADLINE=$(( $(date +%s) + 300 ))
until ssh "${SSH_OPTS[@]}" "root@$IP" true 2>/dev/null; do
  [ "$(date +%s)" -lt "$DEADLINE" ] || { echo "no root SSH on $IP after 300s" >&2; exit 1; }
  sleep 5
done

if [ -n "${ENV_FILE:-}" ]; then
  ssh "${SSH_OPTS[@]}" "root@$IP" 'umask 077 && cat > /root/.env' < "$ENV_FILE"
fi

if [ -n "${DIR:-}" ]; then
  # tar keeps modes and symlinks; --no-same-owner makes root own the files on the box.
  COPYFILE_DISABLE=1 tar --no-xattrs -C "$(dirname "$DIR")" -cf - "$(basename "$DIR")" \
    | ssh "${SSH_OPTS[@]}" "root@$IP" 'tar --no-same-owner -C /root -xf -'
fi

REMOTE="/root/$(basename "$SCRIPT")"
scp -q "${SSH_OPTS[@]}" "$SCRIPT" "root@$IP:$REMOTE"
# ssh joins its args into one remote shell string: %q keeps each arg intact.
# UNIT runs it under systemd-run instead; User=root gives the service root's
# HOME, as an SSH session has.
ssh "${SSH_OPTS[@]}" "root@$IP" "${UNIT:+systemd-run --unit=$UNIT -p User=root }bash $(printf '%q ' "$REMOTE" "$@")"
