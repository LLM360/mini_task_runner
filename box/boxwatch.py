#!/usr/bin/env python3
"""boxwatch.py <dir>: write what this machine is and how it is used into <dir>, until stopped.

  facts.json   instance type, vCPUs, RAM, disk, region, zone, AMI and launch time; at the start
  usage.jsonl  one line a second, with the kernel's own counters:
                 {"t": "2026-10-08T10:15:02.481Z",
                  "cpu": {"user": 1520, "nice": 0, "system": 310, "idle": 98120,   time since boot in
                          "iowait": 75, "irq": 0, "softirq": 12, "steal": 3},      each state, in 1/100 s
                  "mem_available": 7340032000, "disk_used": 6012345678,            bytes, now
                  "net": {"ens5": {"rx": 81234567, "tx": 1234567}, ...}}           bytes since boot
  kernel.log   the kernel's log since boot, written when stopped: a process killed for lack of
               memory shows up there, with the container it was in

SIGTERM, which the conductor sends after the trial, writes kernel.log and ends it at once. Only
Python's standard library is used, so it can start before setup installs anything.
"""
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

DIR = sys.argv[1]
CPU = ["user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"]  # /proc/stat's first columns

# ── What the machine is, and how it is used ───────────────────────────────────────────────────

def facts():
    """From EC2's instance metadata and the kernel. The metadata also holds the account id and the
    box's addresses; they stay out of the record."""
    document = json.loads(metadata("dynamic/instance-identity/document"))
    disk = os.statvfs("/")
    return {"instance_type": document["instanceType"], "vcpus": os.cpu_count(),
            "ram": meminfo()["MemTotal"], "disk": disk.f_blocks * disk.f_frsize,
            "region": document["region"], "zone": document["availabilityZone"],
            "ami": document["imageId"], "launch_time": document["pendingTime"]}

def sample():
    """One line of usage: the kernel's counters as they stand now."""
    disk = os.statvfs("/")
    cpu = open("/proc/stat").readline().split()[1:1 + len(CPU)]
    return {"t": utc_now(), "cpu": dict(zip(CPU, map(int, cpu))),
            "mem_available": meminfo()["MemAvailable"],
            "disk_used": (disk.f_blocks - disk.f_bfree) * disk.f_frsize, "net": network()}

def stop(signum, frame):
    """The trial is over: keep the kernel's log, then end."""
    with open(f"{DIR}/kernel.log", "w") as log:
        subprocess.run(["journalctl", "--dmesg", "--boot", "--output=short-iso-precise", "--utc", "--no-pager"],
                       stdout=log)
    sys.exit()

# ── Small helpers ──────────────────────────────────────────────────────────────────────────────

def metadata(path):
    """One path of EC2's instance metadata, which wants a session token first (IMDSv2)."""
    token = urllib.request.urlopen(urllib.request.Request(
        "http://169.254.169.254/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})).read().decode()
    return urllib.request.urlopen(urllib.request.Request(
        f"http://169.254.169.254/latest/{path}", headers={"X-aws-ec2-metadata-token": token})).read()

def meminfo():
    """/proc/meminfo's kB lines, in bytes: {"MemTotal": 8195919872, "MemAvailable": ..., ...}."""
    return {line.split(":")[0]: int(line.split()[1]) * 1024 for line in open("/proc/meminfo") if line.endswith("kB\n")}

def network():
    """/proc/net/dev: bytes received and sent since boot, per interface."""
    counters = {}
    for line in open("/proc/net/dev").readlines()[2:]:  # after two header lines
        name, numbers = line.split(":", 1)
        numbers = numbers.split()
        counters[name.strip()] = {"rx": int(numbers[0]), "tx": int(numbers[8])}
    return counters

def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

# ── Start ──────────────────────────────────────────────────────────────────────────────────────

os.makedirs(DIR, exist_ok=True)
signal.signal(signal.SIGTERM, stop)
with open(f"{DIR}/facts.json", "w") as f:
    json.dump(facts(), f, indent=1)
with open(f"{DIR}/usage.jsonl", "w", buffering=1) as usage:  # 1: each line is on disk at once
    while True:
        usage.write(json.dumps(sample()) + "\n")
        time.sleep(1)
