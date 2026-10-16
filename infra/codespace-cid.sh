# Lo cargan puente.sh y reiniciar-vault.sh. No hace falta ejecutarlo.
# En Codespaces el hostname a veces no es el nombre del contenedor en Docker.
vault_codespace_cid() {
  local h id name
  h="$(hostname)"
  if docker inspect "$h" >/dev/null 2>&1; then
    printf '%s\n' "$h"
    return 0
  fi

  # cgroup v1: aparece el id completo del contenedor.
  id="$(grep -oE '[0-9a-f]{64}' /proc/self/cgroup 2>/dev/null | head -n 1 || true)"
  if [[ -n "$id" ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi

  # cgroup v2 / cpuset.
  id="$(basename "$(cat /proc/1/cpuset 2>/dev/null || true)")"
  if [[ "$id" =~ ^[0-9a-f]{64}$ ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi

  # Nombre de Docker que contiene el hostname (p. ej. codespaces-xxx…).
  while read -r id name; do
    [[ -z "$id" ]] && continue
    if [[ "$name" == *"$h"* ]]; then
      printf '%s\n' "$id"
      return 0
    fi
  done < <(docker ps --format '{{.ID}} {{.Names}}')

  return 1
}
