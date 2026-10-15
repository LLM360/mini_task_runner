#!/usr/bin/env bash
# services.sh <dir>: write what Docker kept of this trial into <dir>. Harbor stopped the trial's
# containers instead of deleting them (keep_containers), and the box ran one trial, so every
# container, image and build Docker holds is the trial's:
#   <container>/stdout.log, stderr.log  what its main process wrote, each line stamped with its time
#   <container>/inspect.json            docker inspect: image, command, limits, labels, state
#   images.jsonl                        docker image inspect, one line per image: id, tags, digests
#   builds/<id>.json, <id>.log          each image build: its name, status and base images; its output
# Commands run with `docker exec`, as Harbor runs the agent's and the tests', never reach a
# container's logs. Each part stands alone: one failing doesn't stop the rest.
mkdir -p "$1/builds"
cd "$1"
for name in $(docker ps --all --format '{{.Names}}'); do
  mkdir "$name"
  docker logs --timestamps "$name" > "$name/stdout.log" 2> "$name/stderr.log"
  docker inspect "$name" > "$name/inspect.json"
done
for id in $(docker image ls --all --quiet --no-trunc | sort -u); do
  docker image inspect --format '{{json .}}' "$id"
done > images.jsonl
for ref in $(docker buildx history ls --no-trunc --format '{{.Ref}}'); do
  docker buildx history inspect --format json "$ref" > "builds/$ref.json"
  docker buildx history logs "$ref" > "builds/$ref.log" 2>&1  # buildx writes the log to stderr
done
