# Lo cargan puente.sh y reiniciar-vault.sh. No hace falta ejecutarlo.
# En Codespaces el hostname a menudo no es el nombre ni el id del contenedor en Docker.
vault_codespace_cid() {
  local h id name line

  h="$(hostname)"
  if docker inspect "$h" >/dev/null 2>&1; then
    printf '%s\n' "$h"
    return 0
  fi

  # Etiqueta típica de un Codespace (docker-outside-of-docker).
  id="$(docker ps -q --filter 'label=Type=codespaces' | head -n 1 || true)"
  if [[ -n "$id" ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi

  # El Config.Hostname del contenedor sí suele ser codespaces-….
  while read -r id; do
    [[ -z "$id" ]] && continue
    name="$(docker inspect -f '{{.Config.Hostname}}' "$id" 2>/dev/null || true)"
    if [[ "$name" == "$h" ]]; then
      printf '%s\n' "$id"
      return 0
    fi
  done < <(docker ps -q)

  # mountinfo: …/containers/<id64>/hostname → /etc/hostname
  id="$(sed -nE 's|.*/containers/([0-9a-f]{64})/.*|\1|p' /proc/self/mountinfo 2>/dev/null | head -n 1 || true)"
  if [[ -n "$id" ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi

  # cgroup v1 / v2 con el id embebido.
  id="$(grep -oE '[0-9a-f]{64}' /proc/self/cgroup 2>/dev/null | head -n 1 || true)"
  if [[ -n "$id" ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi
  id="$(basename "$(cat /proc/1/cpuset 2>/dev/null || true)")"
  if [[ "$id" =~ ^[0-9a-f]{64}$ ]] && docker inspect "$id" >/dev/null 2>&1; then
    printf '%s\n' "$id"
    return 0
  fi

  # Nombre de Docker que contiene el hostname.
  while read -r id name; do
    [[ -z "$id" ]] && continue
    if [[ "$name" == *"$h"* ]]; then
      printf '%s\n' "$id"
      return 0
    fi
  done < <(docker ps --format '{{.ID}} {{.Names}}')

  # Último recurso: contenedor con /workspaces montado (el del Codespace).
  while read -r id; do
    [[ -z "$id" ]] && continue
    line="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$id" 2>/dev/null || true)"
    if [[ "$line" == *"/workspaces"* ]]; then
      printf '%s\n' "$id"
      return 0
    fi
  done < <(docker ps -q)

  return 1
}
