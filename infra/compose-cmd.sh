# Lo cargan reiniciar-vault.sh y entorno.sh. No hace falta ejecutarlo.
# En el Codespace no se publica el 8200: lo escucha el puente.
vault_compose() {
  local root="$1"
  shift
  local -a files=(-f "$root/infra/compose.yaml")
  if [[ ! -f /.dockerenv ]]; then
    files+=(-f "$root/infra/compose.host.yaml")
  fi
  docker compose "${files[@]}" "$@"
}
