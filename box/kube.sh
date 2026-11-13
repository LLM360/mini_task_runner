#!/usr/bin/env bash
# kube.sh: install helm and kubectl on this box, for a task whose environment is a Helm chart
# (run config: [box] kube = true, and Harbor args that pick `-e helm` with launcher=k3s). Harbor's
# k3s launcher downloads and starts k3s itself but needs these two on PATH first. The versions are
# the ones in alpine/k8s:1.30.2, the image Harbor's sandbox backends run the same charts with.
set -euo pipefail
ARCH=$(dpkg --print-architecture)
curl -fsSL "https://get.helm.sh/helm-v3.15.2-linux-$ARCH.tar.gz" \
  | tar -xz --strip-components=1 -C /usr/local/bin "linux-$ARCH/helm"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.30.2/bin/linux/$ARCH/kubectl"
chmod +x /usr/local/bin/kubectl
helm version --short
kubectl version --client
