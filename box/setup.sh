#!/usr/bin/env bash
# setup.sh <harbor-package>: install the AWS CLI, Docker, uv and Harbor on this box. Harbor is
# <harbor-package>, anything `uv tool install` takes. Everything lands on the trial service's PATH,
# and the versions end the step's log, which is part of the record. The AWS CLI goes first: it is
# all the upload needs.
set -euo pipefail
snap install aws-cli --classic
curl -fsSL https://get.docker.com | sh
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
UV_TOOL_BIN_DIR=/usr/local/bin uv tool install "$1"
docker version
docker compose version
uv --version
harbor --version
