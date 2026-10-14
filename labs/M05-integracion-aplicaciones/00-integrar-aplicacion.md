# Integrar una aplicación

[← Página anterior](README.md) · [Siguiente página →](01-lab-consumo-automatico.md)

La aplicación de pagos necesita `clave` y no debe conocer el token `root`. Esta página monta ese contrato desde cero.

## Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

## Recorrido

1. El secreto, la policy de solo lectura y el rol AppRole `pagos` existen antes de escribir la aplicación. El despliegue recibe `role_id` y `secret_id`. No recibe la clave de la API: esa la pide después.

```bash
vault kv put secret/pagos/api clave=clave-pagos
bash infra/policy.sh solo-pagos <<'EOF'
path "secret/data/pagos/api" {
  capabilities = ["read"]
}
path "secret/metadata/pagos/api" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts/secret/*" {
  capabilities = ["read"]
}
EOF
vault auth enable approle
vault write auth/approle/role/pagos token_policies=solo-pagos token_ttl=15m token_max_ttl=1h
ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
export ROLE_ID SECRET_ID
```

El secreto queda en versión `1`, la policy se registra y AppRole queda habilitado. `ROLE_ID` y `SECRET_ID` quedan en el entorno de esta terminal: son lo único que recibirá el script.

![Secreto, policy y rol AppRole pagos creados en el mismo servidor](../img/M05-00-base.png)

2. El job de CI hace tres cosas y se termina: leer los identificadores del entorno, hacer POST a `/v1/auth/approle/login`, hacer GET a `/v1/secret/data/pagos/api` con el token devuelto. El token `root` no aparece en el script.

```bash
cat > /tmp/ci-pagos.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
login=$(curl -sS --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login")
token=$(printf '%s' "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')
curl -sS --header "X-Vault-Token: ${token}" \
  "${VAULT_ADDR}/v1/secret/data/pagos/api" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"]["clave"])'
EOF
chmod +x /tmp/ci-pagos.sh
/tmp/ci-pagos.sh
```

La clave que imprime es `clave-pagos`.

![El script de CI imprime clave-pagos sin usar el token root](../img/M05-00-script.png)

3. Vault Agent repite ese login él solo. Lee `role_id` y `secret_id` de ficheros, pide el token y renderiza la plantilla en `/tmp/clave-render.txt`.

```bash
printf '%s' "$ROLE_ID" | docker exec -i vault-dev tee /tmp/role_id >/dev/null
printf '%s' "$SECRET_ID" | docker exec -i vault-dev tee /tmp/secret_id >/dev/null
docker exec -i vault-dev tee /tmp/agent.hcl >/dev/null <<'EOF'
pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path = "/tmp/role_id"
      secret_id_file_path = "/tmp/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }
}

template {
  contents = "{{ with secret \"secret/data/pagos/api\" }}{{ .Data.data.clave }}{{ end }}"
  destination = "/tmp/clave-render.txt"
}
EOF
docker exec -d vault-dev vault agent -config=/tmp/agent.hcl
for _i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec vault-dev test -s /tmp/clave-render.txt && break
  sleep 1
done
docker exec vault-dev cat /tmp/clave-render.txt
echo
docker exec vault-dev pkill -f "vault agent" || true
```

El fichero contiene solo `clave-pagos`. La aplicación que «no sabe Vault» leería ese fichero.

![Vault Agent deja clave-pagos en el fichero renderizado](../img/M05-01-agent.png)

La plantilla pide `secret/data/pagos/api` y se queda con `.Data.data.clave`. Si el campo no se llama `clave`, el fichero contiene `<no value>`. El test tiene que decirlo así, no como «Agent no arranca».

## Qué queda visto

Hay dos sitios donde puede vivir la integración: un script que llama a la API, o un fichero renderizado. El [laboratorio](01-lab-consumo-automatico.md) los construye otra vez, con servidor limpio.
