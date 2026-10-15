# shellcheck shell=bash disable=SC2034  # sourced; SSH_KEY/SSH_OPTS are used by the caller
# Source me (bash or zsh): the region and SSH settings for these boxes. The AWS CLI uses your usual
# credentials (AWS_PROFILE, environment variables, ~/.aws); AWS_REGION, if set, picks the region.
#   source ec2/env.sh
export AWS_REGION=${AWS_REGION:-eu-west-1}
export AWS_PAGER=""

# create_one.sh authorizes $SSH_KEY.pub on every box it launches; SSH_OPTS
# connects with $SSH_KEY. Box IPs get recycled, so never record host keys.
# IdentitiesOnly: offer only this key even if the agent holds several.
#   ssh "${SSH_OPTS[@]}" root@<ip>
SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519}
SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes
          -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
