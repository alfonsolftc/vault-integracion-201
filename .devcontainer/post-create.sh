#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 curl ca-certificates openssh-client

export VAULT_DOCKER_INSTALL=1
# shellcheck source=infra/ensure-docker.sh
source "$ROOT/infra/ensure-docker.sh"
_vault_ensure_docker --install

bash "$ROOT/infra/reiniciar-vault.sh"
