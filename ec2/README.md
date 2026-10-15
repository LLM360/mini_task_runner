# ec2

A minimal CLI for disposable EC2 boxes: launch, list, run a script, terminate. Every box powers off, and
is deleted, at its deadline: 12 h after boot unless `MAX_MINUTES` says otherwise.

## Setup, once
- AWS credentials that can launch, describe and terminate EC2 instances. `AWS_REGION` picks the region
  (default `eu-west-1`).
- An SSH key at `~/.ssh/id_ed25519`, or set `SSH_KEY`.
- The security group boxes launch in: SSH, plus Tailscale's UDP port for direct tailnet paths.
```bash
source ec2/env.sh
SG=$(aws ec2 create-security-group --group-name tailnet-direct --description "SSH and Tailscale" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol udp --port 41641 --cidr 0.0.0.0/0
```

## Example
```bash
seq 1 4 | xargs -P 4 -I{} bash ec2/create_one.sh demo {} t3.micro 20
bash ec2/list_fleet.sh demo | ENV_FILE=ec2/examples/hello.vars xargs -P 4 -I{} bash ec2/run_script.sh {} ec2/examples/hello.sh
bash ec2/list_fleet.sh demo | xargs -P 4 -n1 bash ec2/terminate_one.sh
```
