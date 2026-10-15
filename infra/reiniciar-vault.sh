#!/usr/bin/env bash
# Servidor limpio. El modo dev guarda todo en memoria: al recrear el contenedor
# desaparecen secretos, policies y métodos de auth.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# En el Codespace el daemon de Docker arranca con el contenedor.
for _i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  sleep 1
done

# Si esta terminal es el Codespace, suelta la red de Vault antes de borrarla.
if [[ -f /.dockerenv ]] && docker inspect vault-dev >/dev/null 2>&1; then
  _net="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)"
  if [[ -n "${_net}" ]]; then
    docker network disconnect "${_net}" "$(hostname)" >/dev/null 2>&1 || true
  fi
fi

# pagos y pagos-db los arrancan los labs de M05 en la red de Vault.
# Si siguen vivos, compose no puede borrar esa red.
docker rm -f pagos pagos-db >/dev/null 2>&1 || true

docker compose -f "$ROOT/infra/compose.yaml" down
docker compose -f "$ROOT/infra/compose.yaml" up -d

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
