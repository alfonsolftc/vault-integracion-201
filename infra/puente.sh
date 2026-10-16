#!/usr/bin/env bash
# En el Codespace, Vault corre en el Docker del anfitrión y el puerto 8200
# no es siempre el localhost de la terminal. Este puente lo deja en 127.0.0.1:8200.
# En Docker local, si el puerto ya responde, no hace nada.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

http_ok() {
  local code
  code="$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$1" || true)"
  [[ "$code" != "000" && -n "$code" ]]
}

matar_puente_py() {
  if [[ -f /tmp/vault-puente.pid ]]; then
    _old="$(tr -d '[:space:]' < /tmp/vault-puente.pid || true)"
    if [[ -n "${_old}" ]]; then
      kill "${_old}" 2>/dev/null || true
    fi
    rm -f /tmp/vault-puente.pid
  fi
  while read -r _pid _cmd; do
    [[ -z "${_pid}" ]] && continue
    case "${_cmd}" in
      *pgrep*) continue ;;
    esac
    kill "${_pid}" 2>/dev/null || true
  done < <(pgrep -af '/infra/puente.py' || true)
  for _i in $(seq 1 25); do
    if ! pgrep -af '/infra/puente.py' | grep -v pgrep >/dev/null; then
      break
    fi
    sleep 0.2
  done
}

arrancar_puente_py() {
  local vip="$1"
  printf '%s\n' "$vip" > /tmp/vault-puente.upstream
  matar_puente_py
  nohup python3 "$ROOT/infra/puente.py" >/tmp/vault-puente.log 2>&1 &
  echo $! > /tmp/vault-puente.pid
  disown || true
  for _i in $(seq 1 50); do
    if http_ok "http://127.0.0.1:8200/v1/sys/health"; then
      return 0
    fi
    if [[ -f /tmp/vault-puente.pid ]] && ! kill -0 "$(cat /tmp/vault-puente.pid)" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  echo "El puente a Vault no responde en http://127.0.0.1:8200. Revisa /tmp/vault-puente.log" >&2
  if [[ -s /tmp/vault-puente.log ]]; then
    cat /tmp/vault-puente.log >&2
  fi
  return 1
}

# Publica el 8200 en el anfitrión. Sirve cuando el Codespace comparte la red del host
# y no se puede unir a infra_default.
publicar_puerto_host() {
  # shellcheck source=infra/compose-cmd.sh
  source "$ROOT/infra/compose-cmd.sh"
  docker compose \
    -f "$ROOT/infra/compose.yaml" \
    -f "$ROOT/infra/compose.host.yaml" \
    up -d
  unset -f vault_compose
  for _i in $(seq 1 30); do
    if http_ok "http://127.0.0.1:8200/v1/sys/health"; then
      return 0
    fi
    sleep 0.4
  done
  echo "Vault no responde en http://127.0.0.1:8200 tras publicar el puerto." >&2
  return 1
}

if http_ok "http://127.0.0.1:8200/v1/sys/health"; then
  exit 0
fi

if [[ ! -f /.dockerenv ]]; then
  echo "Vault no responde en http://127.0.0.1:8200" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Falta python3 en el Codespace. Vuelve a crear el codespace para que el arranque lo instale." >&2
  exit 1
fi

# shellcheck source=infra/codespace-cid.sh
source "$ROOT/infra/codespace-cid.sh"
cid="$(vault_codespace_cid)" || {
  echo "No encuentro el contenedor de este Codespace en Docker (hostname=$(hostname))." >&2
  echo "Prueba: docker ps --format '{{.ID}} {{.Names}} {{.Label \"Type\"}}'" >&2
  exit 1
}

net="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)"
if [[ -z "$net" ]]; then
  echo "vault-dev no tiene red. Revisa: docker logs vault-dev" >&2
  exit 1
fi

vip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' vault-dev | awk '{print $1}')"
if [[ -z "$vip" ]]; then
  echo "No veo la IP de vault-dev." >&2
  exit 1
fi

modo="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null || true)"
unir=1
if [[ "$modo" == "host" || "$modo" == container:* ]]; then
  unir=0
fi

if [[ "$unir" -eq 1 ]]; then
  connect_status=0
  connect_out="$(docker network connect "$net" "$cid" 2>&1)" || connect_status=$?
  if [[ "$connect_status" -ne 0 && "$connect_out" != *"already exists"* ]]; then
    if [[ "$connect_out" == *"sharing network namespace"* || "$connect_out" == *"cannot be connected"* ]]; then
      unir=0
    else
      echo "No puedo unir este Codespace a la red de Vault (cid=${cid})." >&2
      printf '%s\n' "$connect_out" >&2
      exit 1
    fi
  fi
fi

# Sin unir a la red: o el Codespace ya ve la IP del bridge (red del host),
# o publicamos el 8200 en el anfitrión.
if [[ "$unir" -eq 0 ]]; then
  for _i in $(seq 1 10); do
    if http_ok "http://${vip}:8200/v1/sys/health"; then
      arrancar_puente_py "$vip"
      exit $?
    fi
    sleep 0.3
  done
  publicar_puerto_host
  exit $?
fi

vip_ok=0
for _i in $(seq 1 15); do
  if http_ok "http://${vip}:8200/v1/sys/health"; then
    vip_ok=1
    break
  fi
  sleep 0.4
done
if [[ "$vip_ok" -ne 1 ]]; then
  echo "Este Codespace no llega a vault-dev en ${vip}:8200." >&2
  exit 1
fi

arrancar_puente_py "$vip"
exit $?
