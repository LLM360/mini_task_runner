#!/usr/bin/env bash
# tailnet.sh join <hostname>: join the tailnet as <hostname>, cut to 63 characters (the most a DNS
# label holds), with TS_AUTHKEY from /root/.env. Kernel mode, so this machine reaches tailnet names
# through normal routing and MagicDNS; in-memory state, so the node leaves the tailnet on its own
# once the box is gone; WireGuard on UDP 41641, the port ec2/create_one.sh's default security group
# opens, for a direct path rather than DERP. tailscaled keeps running after this returns.
# tailnet.sh ping <url>...: for each URL's host, one ping that shows how this box reaches it:
# directly ("via <ip>:<port>") or through DERP ("via DERP(<region>)").
set -euo pipefail
if [ "$1" = join ]; then
  source /root/.env  # not exported: tailscaled, started below, never sees the AWS keys
  mkdir -p /root/ts
  curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.102.5_$(dpkg --print-architecture).tgz" \
    | tar -xz --strip-components=1 -C /root/ts
  ln -sf /root/ts/tailscale /usr/local/bin/tailscale
  setsid /root/ts/tailscaled --tun=tailscale0 --state=mem: --port=41641 > /root/tailscaled.log 2>&1 < /dev/null &
  until [ -S /var/run/tailscale/tailscaled.sock ]; do sleep 1; done
  tailscale up --auth-key="$TS_AUTHKEY" --hostname="${2:0:63}" --timeout=60s
  tailscale ip -4
else
  for url in "${@:2}"; do
    host=${url#*://}
    tailscale ping -c 1 --until-direct=false "${host%%[:/]*}"
  done
fi
