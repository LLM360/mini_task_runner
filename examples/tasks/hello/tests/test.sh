#!/usr/bin/env bash
# Reward 1 if /app/hello.txt holds exactly "Hello, world!", else 0.
if [ "$(cat /app/hello.txt 2>/dev/null)" = "Hello, world!" ]; then echo 1; else echo 0; fi > /logs/verifier/reward.txt
