# Carga con: source infra/ensure-docker.sh
# Opcional: VAULT_DOCKER_INSTALL=1 para instalar docker.io en el Codespace si falta el CLI.
_vault_ensure_docker() {
  local _install="${VAULT_DOCKER_INSTALL:-0}"

  if [[ "${1:-}" == "--install" ]]; then
    _install=1
  fi

  export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

  if [[ -z "${DOCKER_HOST:-}" ]]; then
    if [[ -S /var/run/docker-host.sock ]]; then
      export DOCKER_HOST=unix:///var/run/docker-host.sock
    elif [[ -S /var/run/docker.sock ]]; then
      export DOCKER_HOST=unix:///var/run/docker.sock
    fi
  fi

  local _i
  for _i in $(seq 1 90); do
    command -v docker >/dev/null 2>&1 && break
    sleep 1
  done

  if ! command -v docker >/dev/null 2>&1 && [[ -f /.dockerenv ]] && [[ "$_install" == 1 ]]; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      docker.io ca-certificates curl >/dev/null
    if ! docker compose version >/dev/null 2>&1; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        docker-compose-v2 2>/dev/null \
        || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          docker-compose-plugin 2>/dev/null \
        || true
    fi
  fi

  if ! command -v docker >/dev/null 2>&1; then
    cat >&2 <<'EOF'
No encuentro el comando docker.

Si estás en GitHub Codespace:
  1. Espera a que termine de crearse el entorno (postCreate).
  2. Paleta (Ctrl+Shift+P) → "Codespaces: Rebuild Container".
  3. Abre el codespace desde tu fork: Code → Create codespace on main
     (no basta con github.dev sin devcontainer).

Si estás en tu PC: instala Docker Desktop o el motor Docker y vuelve a intentar.
EOF
    return 127
  fi

  for _i in $(seq 1 90); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Docker está instalado pero no responde (docker info). Espera un minuto y ejecuta de nuevo: bash infra/reiniciar-vault.sh" >&2
  return 1
}
