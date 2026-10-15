#!/usr/bin/env bash
# Launch ONE raw EC2 box: latest Ubuntu 24.04 for the instance type's CPU
# architecture, root SSH for your $SSH_KEY.pub (env.sh), tagged Project=mini-task-runner,
# Fleet=<fleet>, Name=<fleet>-<suffix>. Does NOT wait for it to boot (poll
# with list_fleet.sh). Every box has a deadline: it powers itself off MAX_MINUTES
# after boot (720, 12 h, unless set), and a poweroff, at the deadline or from
# inside, deletes the box and its disk. To end one sooner, use terminate_one.sh.
#
#   bash ec2/create_one.sh <fleet> [<suffix>] [<instance-type>] [<disk-gb>]   # prints the instance ID
#   bash ec2/create_one.sh demo 1                            # c7i.4xlarge, 320 GB, gone 12 h after boot
#   bash ec2/create_one.sh fleet-test arm t4g.micro 20
#   MAX_MINUTES=180 bash ec2/create_one.sh my-trial 1 m7i.xlarge   # gone 3 h after boot
#
# <suffix> defaults to 4 random hex chars (pass "" to keep that default while
# setting a later arg). <fleet> and <suffix> must match [a-zA-Z0-9_-]+.
set -euo pipefail
source "$(dirname "$0")/env.sh"

USAGE="usage: create_one.sh <fleet> [<suffix>] [<instance-type>] [<disk-gb>]"
FLEET="${1:?$USAGE}"
SUFFIX="${2:-$(openssl rand -hex 2)}"
INSTANCE_TYPE="${3:-c7i.4xlarge}"
DISK_GB="${4:-320}"
MAX_MINUTES="${MAX_MINUTES:-720}"
# Inbound SSH plus UDP 41641, Tailscale's port, so tailnet peers behind hard NATs get direct
# paths instead of DERP relays. It must exist in the region; SG_NAME picks another group.
SG_NAME="${SG_NAME:-tailnet-direct}"

[[ "$FLEET"   =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "fleet must match [a-zA-Z0-9_-]+" >&2; exit 1; }
[[ "$SUFFIX"  =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "suffix must match [a-zA-Z0-9_-]+" >&2; exit 1; }
[[ "$DISK_GB" =~ ^[0-9]+$ ]]         || { echo "disk-gb must be a whole number" >&2; exit 1; }

[ -f "$SSH_KEY.pub" ] || { echo "public key not found: $SSH_KEY.pub (set SSH_KEY to another key)" >&2; exit 1; }

SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text)
[ "$SG_ID" != None ] || { echo "security group $SG_NAME not found" >&2; exit 1; }

# The AMI must match the instance's CPU: c7g/t4g are arm64, c7i/m7i are x86_64.
ARCHES=" $(aws ec2 describe-instance-types --instance-types "$INSTANCE_TYPE" \
  --query 'InstanceTypes[0].ProcessorInfo.SupportedArchitectures' --output text | tr '\t' ' ') "
case "$ARCHES" in
  *" arm64 "*)  UBUNTU_ARCH=arm64 ;;
  *" x86_64 "*) UBUNTU_ARCH=amd64 ;;
  *) echo "unsupported architectures for $INSTANCE_TYPE:$ARCHES" >&2; exit 1 ;;
esac

read -r AMI_ID ROOT_DEV <<<"$(aws ec2 describe-images --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-$UBUNTU_ARCH-server-*" \
            'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].[ImageId,RootDeviceName]' --output text)"

# cloud-init authorizes the key for ubuntu, then the runcmd mirrors it to root.
# The deadline goes first: shutdown -h powers off, and a poweroff terminates.
USER_DATA="#cloud-config
disable_root: false
ssh_authorized_keys:
  - $(cat "$SSH_KEY.pub")
runcmd:
  - shutdown -h +$MAX_MINUTES
  - install -d -m 0700 -o root -g root /root/.ssh
  - cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
  - chown root:root /root/.ssh/authorized_keys"

NAME="$FLEET-$SUFFIX"
echo "launching $NAME: $INSTANCE_TYPE ($UBUNTU_ARCH), ${DISK_GB} GB, $AMI_ID, powers off $MAX_MINUTES min after boot" >&2

# DeleteOnTermination=true is load-bearing: without it the root volume
# outlives the instance and keeps billing. Terminate on shutdown: any poweroff
# from inside (or the MAX_MINUTES deadline) deletes the box. Hop limit 1: the
# box itself can read its instance metadata, the containers it runs can't.
aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --security-group-ids "$SG_ID" \
  --user-data "$USER_DATA" \
  --instance-initiated-shutdown-behavior terminate \
  --metadata-options 'HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1' \
  --block-device-mappings "[{\"DeviceName\":\"$ROOT_DEV\",\"Ebs\":{\"VolumeSize\":$DISK_GB,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true,\"Encrypted\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=mini-task-runner},{Key=Fleet,Value=$FLEET},{Key=Name,Value=$NAME}]" \
  --count 1 \
  --query 'Instances[0].InstanceId' --output text
