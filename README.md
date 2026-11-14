# mini_task_runner

Runs one [Harbor](https://github.com/harbor-framework/harbor) task on its own EC2 box with full
observability: everything about the trial lands in S3 for post-mortem analysis. The box deletes itself.

## You need
- `uv`, the AWS CLI v2 and `ssh`.
- AWS credentials that can launch EC2 boxes (one-time setup in [ec2/](ec2/README.md)) and either call
  `sts:GetFederationToken` or take on a role that can write your bucket.
- An OpenAI-compatible endpoint the box can reach. To reach a model on a private machine, put it on your
  tailnet with [tailscale_relay](https://github.com/aldopareja/tailscale_relay).

## Run
```bash
./run examples/tasks/hello examples/run_configs/oracle.toml   # prints <trial-id> <ip> <record-url>
```
Copy a file from `examples/run_configs/` to write your own; its comments explain every field.
- `RECORD_ROLE=<role-arn>`: if only a role can write your bucket.
- `RECORD_PRESIGN=1`: if your credentials can do neither. The box gets no AWS key, only signed permission to upload into its trial's folder (`presign.py`; 5 GB a file at most).
- `TS_AUTHKEY=<key>`: if the endpoint is only on your tailnet.

## Watch, stop
```bash
source ec2/env.sh && ssh "${SSH_OPTS[@]}" root@<ip> journalctl -fu trial   # follow the trial
bash ec2/terminate_one.sh <ip>                                            # stop it early; its record is lost
```

## The record
```
<record>/<trial-id>/
├── spec.json      the run config, plus the trial id, task name and launch time
├── task/          the task as it ran
├── runner/        the box scripts that ran it
├── harbor/        Harbor's trial folder: result.json (the reward), agent/, verifier/, trial.log
├── model_calls/   every model call, one file per call, written as it happens
├── services/      each container's output and settings, the images, each image build's log
├── box/           the machine: facts, usage every second, kernel log; steps/ has each step's log
└── upload.json    every file uploaded and its size; written last, so it marks the record complete
```
