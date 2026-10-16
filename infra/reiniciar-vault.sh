#!/usr/bin/env bash
# Servidor limpio. El modo dev guarda todo en memoria: al recrear el contenedor
# desaparecen secretos, policies y métodos de auth.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=infra/ensure-docker.sh
source "$ROOT/infra/ensure-docker.sh"
# shellcheck source=infra/compose-cmd.sh
source "$ROOT/infra/compose-cmd.sh"

if [[ -f /.dockerenv ]]; then
  export VAULT_DOCKER_INSTALL=1
fi
_vault_ensure_docker ${VAULT_DOCKER_INSTALL:+--install}

# Si esta terminal es el Codespace, suelta la red de Vault antes de borrarla.
# shellcheck source=infra/codespace-cid.sh
source "$ROOT/infra/codespace-cid.sh"
if [[ -f /.dockerenv ]] && docker inspect vault-dev >/dev/null 2>&1; then
  _net="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)"
  _cid="$(vault_codespace_cid 2>/dev/null || true)"
  if [[ -n "${_net}" && -n "${_cid}" ]]; then
    docker network disconnect "${_net}" "${_cid}" >/dev/null 2>&1 || true
  fi
fi

# pagos y pagos-db los arrancan los labs de M05 en la red de Vault.
# destino es el sshd del laboratorio de SSH. Si siguen vivos, compose
# no puede borrar esa red, y el puerto 2222 queda ocupado.
docker rm -f pagos pagos-db destino >/dev/null 2>&1 || true

vault_compose "$ROOT" down
vault_compose "$ROOT" up -d

listo=0
for _i in $(seq 1 30); do
  if docker exec \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN=root \
    vault-dev vault status >/dev/null 2>&1; then
    listo=1
    break
  fi
  sleep 1
done

if [[ "$listo" -ne 1 ]]; then
  echo "Vault no ha respondido. Revisa: docker logs vault-dev" >&2
  exit 1
fi

bash "$ROOT/infra/puente.sh"

echo "Vault limpio en http://127.0.0.1:8200  token: root"
echo "En esta misma terminal: source infra/entorno.sh"
