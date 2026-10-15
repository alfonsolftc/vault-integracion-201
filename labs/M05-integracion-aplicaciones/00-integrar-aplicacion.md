# Integrar una aplicación

[← Página anterior](README.md) · [Siguiente página →](01-lab-consumo-automatico.md)

La aplicación de pagos necesita `clave` y dice en voz alta cuál está usando. Hay dos maneras de entregársela. En la primera, la propia app hace login y llama a la API. En la segunda, Vault Agent —un proceso al lado de la app, no un servicio del servidor— escribe la clave en un fichero y la app solo lo lee.

## Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

`vault-dev` es el servidor, vacío. La terminal queda con `VAULT_ADDR=http://127.0.0.1:8200` y el token `root` de laboratorio. Ese token no entra en la aplicación.

## Recorrido

1. El secreto, la policy de solo lectura y el rol AppRole `pagos` existen antes de escribir la aplicación. El despliegue recibe `role_id` y `secret_id`. La clave la pide después.

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

El secreto queda en versión `1`, la policy se registra y AppRole queda habilitado. `ROLE_ID` y `SECRET_ID` quedan en esta terminal.

![Secreto, policy y rol AppRole pagos creados en el mismo servidor](../img/M05-00-base.png)

2. `/tmp/app-pagos.sh` es la aplicación. Corre en esta terminal, que hace de máquina del proceso. Hace el POST de login, el GET del secreto y usa la clave: la imprime en una frase. El token `root` no aparece en el script. El token de AppRole se queda en una variable y tampoco se imprime.

```bash
cat > /tmp/app-pagos.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
login=$(curl -sS --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login")
token=$(printf '%s' "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')
clave=$(curl -sS --header "X-Vault-Token: ${token}" \
  "${VAULT_ADDR}/v1/secret/data/pagos/api" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"]["clave"])')
echo "Hola, soy la app de pagos y estoy usando la clave ${clave}"
EOF
chmod +x /tmp/app-pagos.sh
/tmp/app-pagos.sh
```

La línea es `Hola, soy la app de pagos y estoy usando la clave clave-pagos`.

![La app llama a la API e imprime la clave que está usando](../img/M05-00-app.png)

3. La otra entrega deja de hablar con Vault. Vault Agent es quien hace el login. Para eso hace falta una máquina que sea la de la aplicación, distinta de `vault-dev`. El contenedor `pagos` es esa máquina: se une a la red de Docker del servidor y se queda encendido con `sleep`. `sleep` no es la app. Solo mantiene el contenedor vivo para poder copiar ficheros y arrancar procesos.

```bash
docker rm -f pagos >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
docker run -d --name pagos --network "$RED" --entrypoint sleep hashicorp/vault:1.18 86400
```

`red=` muestra el nombre de la red, en este laboratorio `infra_default`. El contenedor `pagos` queda en marcha. Desde ahí, `127.0.0.1` es el propio contenedor: Vault no escucha en esa dirección. El servidor se alcanza por el nombre `vault-dev`.

4. Dentro de `pagos` se dejan cuatro cosas. Los dos identificadores, porque Agent no ve las variables de esta terminal. La aplicación, que solo lee un fichero. Y `agent.hcl`, que es la configuración entera de Agent:

| Bloque | Para qué está |
|--------|----------------|
| `pid_file` | Número de proceso, para parar Agent sin borrar la máquina |
| `vault.address` | `http://vault-dev:8200`, el servidor visto desde `pagos` |
| `auto_auth` | El mismo login AppRole de la app anterior. Los identificadores salen de fichero |
| `remove_secret_id_file_after_reading = false` | El fichero del `secret_id` sigue ahí, y Agent puede arrancar otra vez. Con `true` lo borraría tras el primer login |
| `template` | Hace el GET de `secret/data/pagos/api`, se queda con `.Data.data.clave` y lo escribe en `/tmp/clave.txt` |

La plantilla es la de Consul Template, que Agent lleva dentro. `with secret "…"` es la lectura. En un KV v2 el campo está en `.Data.data`, con esa mayúscula. Si el campo no se llama `clave`, el fichero queda con el texto `<no value>`.

```bash
printf '%s' "$ROLE_ID" | docker exec -i pagos tee /tmp/role_id >/dev/null
printf '%s' "$SECRET_ID" | docker exec -i pagos tee /tmp/secret_id >/dev/null
docker exec -i pagos tee /tmp/app.sh >/dev/null <<'EOF'
#!/bin/sh
if [ ! -s /tmp/clave.txt ]; then
  echo "no hay fichero de secreto" >&2
  exit 1
fi
clave=$(cat /tmp/clave.txt)
echo "Hola, soy la app de pagos y estoy usando la clave ${clave}"
EOF
docker exec -i pagos tee /tmp/agent.hcl >/dev/null <<'EOF'
pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://vault-dev:8200"
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
  destination = "/tmp/clave.txt"
}
EOF
```

Los `tee` terminan sin texto. `app.sh` no contiene `VAULT_ADDR`, ni un token, ni `role_id`.

5. Agent arranca dentro de `pagos` y deja el log en `/tmp/agent.log`. El proceso principal del contenedor es `sleep`, así que `docker logs pagos` no cuenta esta salida. Cuando el fichero tiene contenido, la app lo lee.

```bash
docker exec -d pagos sh -c 'vault agent -config=/tmp/agent.hcl > /tmp/agent.log 2>&1'
for _i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec pagos test -s /tmp/clave.txt && break
  sleep 1
done
docker exec pagos grep -F -e 'authentication successful' -e 'rendered "(dynamic)"' /tmp/agent.log
docker exec pagos sh /tmp/app.sh
docker rm -f pagos >/dev/null
```

El log tiene dos frases: `authentication successful` (el login AppRole ya está hecho) y `rendered "(dynamic)" => "/tmp/clave.txt"` (la plantilla ya escribió el fichero). La app imprime la misma frase que la del paso 2: `Hola, soy la app de pagos y estoy usando la clave clave-pagos`. Al final el contenedor `pagos` desaparece. El servidor `vault-dev` sigue.

![Agent entra, escribe el fichero y la app lee la clave](../img/M05-00-agent.png)

## Qué queda visto

La misma frase sale de dos sitios. La app de la terminal habla con Vault. La app de `pagos` habla con un fichero, y quien habla con Vault es Agent. El [laboratorio](01-lab-consumo-automatico.md) construye las dos otra vez. El job de CI, con códigos de salida, está en [el job que falla cerrado](02-lab-job-falla-cerrado.md). Postgres, con un usuario nuevo en cada arranque, está en [la app entra en Postgres](04-lab-credencial-de-postgres.md).
