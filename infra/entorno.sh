#!/usr/bin/env bash
# Uso: source infra/entorno.sh
# Deja Vault en marcha y exporta VAULT_ADDR y VAULT_TOKEN.
# No borra datos. Para un servidor limpio, antes: bash infra/reiniciar-vault.sh

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Este fichero se carga con: source infra/entorno.sh" >&2
  exit 1
fi

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=infra/ensure-docker.sh
source "$_ROOT/infra/ensure-docker.sh"
# shellcheck source=infra/compose-cmd.sh
source "$_ROOT/infra/compose-cmd.sh"
if [[ -f /.dockerenv ]]; then
  export VAULT_DOCKER_INSTALL=1
fi
_vault_ensure_docker ${VAULT_DOCKER_INSTALL:+--install} || return 1
vault_compose "$_ROOT" up -d
unset -f vault_compose _vault_ensure_docker

_listo=0
for _i in $(seq 1 30); do
  if docker exec \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN=root \
    vault-dev vault status >/dev/null 2>&1; then
    _listo=1
    break
  fi
  sleep 1
done

if [[ "$_listo" -ne 1 ]]; then
  echo "Vault no ha respondido a tiempo. Revisa: docker logs vault-dev" >&2
  return 1
fi

bash "$_ROOT/infra/puente.sh"

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root

if ! command -v vault >/dev/null 2>&1; then
  vault() {
    docker exec \
      -e VAULT_ADDR=http://127.0.0.1:8200 \
      -e VAULT_TOKEN="${VAULT_TOKEN:-root}" \
      vault-dev vault "$@"
  }
  export -f vault
fi

echo "VAULT_ADDR=$VAULT_ADDR"
echo "VAULT_TOKEN=$VAULT_TOKEN  (solo laboratorio, modo dev)"
