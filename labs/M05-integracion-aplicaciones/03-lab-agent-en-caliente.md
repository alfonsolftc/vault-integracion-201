# Agent y el cambio en caliente

[← Página anterior](02-lab-job-falla-cerrado.md) · [Siguiente página →](04-lab-credencial-de-postgres.md)

La app de `pagos` lee `/tmp/clave.txt` cada vez que arranca. Quien se entera de una rotación es Vault Agent, que vuelve a escribir el fichero. Con un KV v2 el secreto no tiene lease: Agent solo vuelve a leer si el `agent.hcl` le pone un intervalo. Vas a ver la misma app decir primero `clave-v1` y después `clave-v2`, sin volver a arrancar Agent y sin tocar `app.sh`.

### Objetivo

`sh /tmp/app.sh` dentro de `pagos` imprime la frase con `clave-v1` y, tras otra escritura en Vault, la misma frase con `clave-v2`.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. El contenedor `pagos` se crea en esta página. Quítalo al final: el comando está en el reto y en el aviso de abajo.

### En qué consiste

AppRole, la máquina de la app, Agent con intervalo de render, la primera frase, la rotación y la segunda frase.

### 1 — Secreto, policy y rol

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-v1
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
vault write auth/approle/role/pagos \
  token_policies=solo-pagos \
  token_ttl=15m \
  token_max_ttl=1h
ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
export ROLE_ID SECRET_ID
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** Agent entra con AppRole. El `secret_id` de este rol no tiene límite de usos: lo lee del fichero y puede volver a autenticarse.

**Resultado esperado:** `role_len=36 secret_len=36`.

### 2 — Arranca la máquina de la app y deja los ficheros

**Acción:**

```bash
docker rm -f pagos >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
docker run -d --name pagos --network "$RED" --entrypoint sleep hashicorp/vault:1.18 86400
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

template_config {
  static_secret_render_interval = "5s"
}

template {
  contents = "{{ with secret \"secret/data/pagos/api\" }}{{ .Data.data.clave }}{{ end }}"
  destination = "/tmp/clave.txt"
}
EOF
```

**Por qué:** la lectura de un KV v2 vuelve con `lease_duration` 0. Sin `static_secret_render_interval`, Agent escribe el fichero una vez y se queda en el valor viejo aunque tú guardes la versión 2. Cinco segundos es el ritmo de este laboratorio. `address` es `http://vault-dev:8200` porque Agent corre en `pagos`, no en el servidor. `app.sh` solo lee `/tmp/clave.txt`.

**Resultado esperado:** `docker run` imprime un id. Los `tee` terminan sin texto.

### 3 — Arranca Agent y lee la primera versión

**Acción:**

```bash
docker exec pagos rm -f /tmp/clave.txt
docker exec -d pagos sh -c 'vault agent -config=/tmp/agent.hcl > /tmp/agent.log 2>&1'
for _i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec pagos test -s /tmp/clave.txt && break
  sleep 1
done
docker exec pagos sh /tmp/app.sh
```

**Por qué:** la frase es lo que compruebas. Sale de `app.sh`, que no sabe que Vault existe.

**Resultado esperado:** `Hola, soy la app de pagos y estoy usando la clave clave-v1`. El bucle no agota los 10 intentos.

![La app lee clave-v1 del fichero que acaba de escribir Agent](../img/M05-03-v1.png)

### 4 — Rota el secreto y vuelve a ejecutar la app

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-v2
sleep 8
docker exec pagos sh /tmp/app.sh
```

**Por qué:** nadie reinicia Agent ni reescribe `app.sh`. A los cinco segundos Agent vuelve a pedir el secreto y reescribe `/tmp/clave.txt`. Ocho segundos dejan margen para ese ciclo. La app, al arrancar otra vez, lee lo que hay en el fichero.

**Resultado esperado:** `Hola, soy la app de pagos y estoy usando la clave clave-v2`.

![Ocho segundos después la misma app dice clave-v2](../img/M05-03-v2.png)

### 5 — Para Agent

**Acción:**

```bash
docker exec pagos sh -c 'if [ -f /tmp/vault-agent.pid ]; then kill $(cat /tmp/vault-agent.pid) || true; fi'
```

**Por qué:** el contenedor sigue, así que el fichero sigue. Agent ya no lo reescribe. `pid_file` es el número de proceso que puso el propio `agent.hcl`.

**Resultado esperado:** el comando termina. No imprime la clave.

> [!WARNING]
> `static_secret_render_interval` hace que Agent siga leyendo el secreto mientras el proceso viva. Al cerrar el ejercicio: `docker rm -f pagos`.

## Comprueba tu entendimiento

**Con Agent parado, el fichero se queda como está**
`vault kv put secret/pagos/api clave=clave-v3` y, sin esperar, `docker exec pagos sh /tmp/app.sh`.
→ La frase sigue con `clave-v2`. No hay nadie renderizando. El contenedor `pagos` tiene que seguir existiendo; si ya lo borraste, el `docker exec` falla y este paso no aplica.

## Reto

### 1 — Vuelve a arrancar Agent y recoge la versión 3

Si hiciste la comprobación, el secreto ya es `clave-v3` y el fichero no. Arranca Agent otra vez con la misma config, espera la frase y quita el contenedor.

<details>
<summary>Ver solución</summary>

```bash
docker exec pagos rm -f /tmp/clave.txt /tmp/vault-agent.pid
docker exec -d pagos sh -c 'vault agent -config=/tmp/agent.hcl > /tmp/agent.log 2>&1'
for _i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec pagos test -s /tmp/clave.txt && break
  sleep 1
done
docker exec pagos sh /tmp/app.sh
docker rm -f pagos >/dev/null
```

La frase lleva `clave-v3`. Borrar el fichero antes de arrancar obliga a un render nuevo con el valor que hay ahora en Vault.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| La app imprime `no hay fichero de secreto` | Agent no arrancó o la policy no deja leer | `docker exec pagos cat /tmp/agent.log` |
| El paso 4 sigue en `clave-v1` | Falta `static_secret_render_interval` o no esperaste | Revisa el `agent.hcl` del paso 2 y espera otro ciclo de 8 segundos |
| La frase dice `<no value>` | La plantilla no usa `.Data.data.clave` | Vuelve a copiar el bloque `template` del paso 2 |
| `No such container: pagos` en la comprobación | Ya ejecutaste `docker rm -f pagos` | La comprobación va antes de borrar el contenedor |
