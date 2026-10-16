# Escenarios de fallo

[← Página anterior](00-disenar-pruebas.md) · [Siguiente página →](02-lab-checklist.md)

Vas a construir la aplicación de pagos y provocar, uno a uno, los fallos del temario. Cada paso es una acción y dice el resultado antes de que mires la pantalla.

### Objetivo

Dejar anotado, con una salida real, el caso feliz y estos seis: token caducado, permiso denegado, secreto ausente, versión vieja tras rotar, lectura en caliente y Vault en pausa.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
unset APP_TOKEN CAMINO QUERY
```

Servidor vacío. El script de la aplicación se escribe en esta página. `unset` evita que un `APP_TOKEN` de otro ejercicio en esta misma terminal se cuele en el script y convierta el caso feliz en un 403 de token muerto.

### En qué consiste

Un script `/tmp/app-pagos.sh` que usa AppRole salvo que le pases `APP_TOKEN`. Cada fallo cambia una sola cosa —el token, el rol, el camino, la versión, el valor o la red— y vuelve a lanzar el script.

### 1 — Guarda la primera clave

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-v1
```

**Por qué:** es el valor del caso feliz y el que tiene que seguir existiendo cuando el fallo sea de token o de policy.

**Resultado esperado:** la metadata muestra `version` `1`.

### 2 — Registra la policy de pagos

**Acción:**

```bash
bash infra/policy.sh solo-pagos <<'EOF'
path "secret/data/pagos/api" {
  capabilities = ["read"]
}
path "secret/data/pagos/no-existe" {
  capabilities = ["read"]
}
path "secret/metadata/pagos/*" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts/secret/*" {
  capabilities = ["read"]
}
EOF
```

**Por qué:** el camino `pagos/no-existe` entra ya en la policy. Así el 404 de más adelante es por el dato, no por un 403 de permiso.

**Resultado esperado:** `Policy solo-pagos escrita.`

### 3 — Habilita AppRole y crea el rol pagos

**Acción:**

```bash
vault auth enable approle
vault write auth/approle/role/pagos token_policies=solo-pagos token_ttl=15m token_max_ttl=1h
```

**Por qué:** la aplicación entra con AppRole. El token `root` se queda para las comprobaciones de administración.

**Resultado esperado:** `Success! Enabled approle auth method at: approle/` y `Success! Data written to: auth/approle/role/pagos`.

### 4 — Exporta los identificadores de pagos

**Acción:**

```bash
export ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** el script los hereda de esta terminal. La línea visible es la longitud, no el valor.

**Resultado esperado:** `role_len=36 secret_len=36`.

### 5 — Escribe la aplicación

**Acción:**

```bash
cat > /tmp/app-pagos.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${APP_TOKEN:-}" ]]; then
  token="$APP_TOKEN"
else
  login=$(curl -sS --request POST \
    --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
    "${VAULT_ADDR}/v1/auth/approle/login")
  token=$(printf '%s' "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')
fi
url="${VAULT_ADDR}/v1/secret/data/${CAMINO:-pagos/api}${QUERY:-}"
code=$(curl -sS --max-time 5 -o /tmp/app-body.json -w "%{http_code}" \
  --header "X-Vault-Token: ${token}" "$url" || echo "000")
echo "http=${code}"
python3 -m json.tool /tmp/app-body.json 2>/dev/null || true
echo
EOF
chmod +x /tmp/app-pagos.sh
```

**Por qué:** `APP_TOKEN` salta el login cuando el caso es un token ya creado. `CAMINO` y `QUERY` cambian el GET sin editar el script. Si `curl` no llega, el código que se imprime es `000`.

**Resultado esperado:** termina sin texto.

### 6 — Lanza el caso feliz

**Acción:**

```bash
/tmp/app-pagos.sh
```

**Por qué:** sin el 200 de referencia, un fallo posterior no se distingue de «el script nunca funcionó».

**Resultado esperado:** `http=200` y en el JSON `"clave": "clave-v1"`.

![Caso feliz: http=200 y clave-v1](../img/M06-01-feliz.png)

### 7 — Lee con un token de cinco segundos

**Acción:**

```bash
CORTO=$(vault token create -policy=solo-pagos -ttl=5s -explicit-max-ttl=5s -field=token)
APP_TOKEN="$CORTO" /tmp/app-pagos.sh
```

**Por qué:** la aplicación reutiliza un token que todavía vale. No hace login nuevo. `explicit-max-ttl` impide que el TTL se alargue.

**Resultado esperado:** `http=200` y `clave-v1`. `CORTO` queda en esta terminal para el paso siguiente.

### 8 — Espera y lee con el mismo token

**Acción:**

```bash
sleep 6
APP_TOKEN="$CORTO" /tmp/app-pagos.sh || true
unset APP_TOKEN
```

**Por qué:** a los seis segundos el token ya no vale. El `unset` evita que el resto de la página herede ese 403.

**Resultado esperado:** `http=403`. El cuerpo lleva `invalid token` y no muestra `clave-v1`.

![Token vigente http=200; seis segundos después http=403 invalid token](../img/M06-01-ttl.png)

### 9 — Registra una policy que no lee pagos

**Acción:**

```bash
bash infra/policy.sh sin-pagos <<'EOF'
path "secret/data/nominas/api" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts/secret/*" {
  capabilities = ["read"]
}
EOF
```

**Por qué:** el 403 de permiso necesita un rol cuyo login sea válido y cuya policy mire otro camino.

**Resultado esperado:** `Policy sin-pagos escrita.`

### 10 — Entra con ese rol y lee pagos

**Acción:**

```bash
vault write auth/approle/role/sin-pagos token_policies=sin-pagos token_ttl=15m token_max_ttl=1h
export ROLE_ID=$(vault read -field=role_id auth/approle/role/sin-pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/sin-pagos/secret-id)
/tmp/app-pagos.sh || true
```

**Por qué:** este `export` pisa los identificadores de `pagos`. El script hace un login nuevo, válido, y el GET cae en la policy. El secreto de pagos existe.

**Resultado esperado:** `http=403` y `permission denied`.

### 11 — Lee la clave con el token root

**Acción:**

```bash
source infra/entorno.sh
vault kv get -field=clave secret/pagos/api
```

**Por qué:** el 403 del paso anterior no ha borrado el dato. `source` devuelve `VAULT_TOKEN` a `root`. No toca `ROLE_ID`; el paso 12 lo vuelve a exportar igual.

**Resultado esperado:** `clave-v1`.

![Rol sin permiso de pagos: http=403; con root la clave sigue](../img/M06-01-permiso.png)

### 12 — Pide un camino que no existe

**Acción:**

```bash
export ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
CAMINO=pagos/no-existe /tmp/app-pagos.sh || true
unset CAMINO
```

**Por qué:** el token de `pagos` puede leer ese camino (la policy del paso 2) y no hay dato. Si fuera un 403, habrías probado otra cosa. El `unset` devuelve el camino por defecto.

**Resultado esperado:** `http=404`. El cuerpo no trae `clave-v1`.

![Camino que no existe: http=404](../img/M06-01-404.png)

### 13 — Escribe la versión 2

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-v2
```

**Por qué:** la rotación deja dos versiones. La prueba que se queda en la 1 y la que lee la vigente tienen que poder distinguirse.

**Resultado esperado:** la metadata muestra `version` `2`.

### 14 — Lee solo la versión 1

**Acción:**

```bash
QUERY='?version=1' /tmp/app-pagos.sh
```

**Por qué:** las dos respuestas van a ser HTTP 200. El defecto está en afirmar la versión nueva cuando la petición pide la 1.

**Resultado esperado:** `clave-v1` y `"version": 1`. `QUERY` sigue definido para el paso siguiente, que lo quita.

### 15 — Lee la versión vigente

**Acción:**

```bash
unset QUERY
/tmp/app-pagos.sh
```

**Por qué:** sin query, KV v2 devuelve la última versión. Rotación incorrecta, en la prueba, es confundir esta lectura con la del paso 14.

**Resultado esperado:** `clave-v2` y `"version": 2`.

![?version=1 sigue en clave-v1; la lectura sin versión ya es clave-v2](../img/M06-01-rota.png)

### 16 — Primera lectura en caliente

**Acción:**

```bash
echo "--- lectura 1 ---"
/tmp/app-pagos.sh
```

**Por qué:** esta línea es el antes. El script pide el secreto cada vez; no guarda la clave de una ejecución anterior.

**Resultado esperado:** `clave-v2`, que es la vigente desde el paso 13.

### 17 — Cambia el valor sin reiniciar

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-viva
```

**Por qué:** nadie reinicia la aplicación ni Vault. Una aplicación que caché la clave en memoria no vería este cambio: ese sería otro caso.

**Resultado esperado:** la metadata muestra `version` `3`.

### 18 — Segunda lectura

**Acción:**

```bash
echo "--- lectura 2 ---"
/tmp/app-pagos.sh
```

**Por qué:** el mismo script, lanzado otra vez, tiene que ver el valor nuevo.

**Resultado esperado:** `clave-viva`.

![Dos lecturas sin reiniciar: la segunda ve clave-viva](../img/M06-01-vivo.png)

### 19 — Pausa el servidor

**Acción:**

```bash
docker pause vault-dev
```

**Por qué:** la pausa congela el proceso sin borrar la memoria. Un `docker restart` en modo dev vaciaría los secretos y mezclaría «caída» con «dato perdido».

**Resultado esperado:** el comando imprime `vault-dev`.

### 20 — Intenta leer durante la pausa

**Acción:**

```bash
curl -sS --max-time 3 -o /tmp/pausa.json -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/pagos/api" || true
```

**Por qué:** aquí no hay 200 ni 403. El síntoma es que la llamada no completa.

**Resultado esperado:** `curl: (28) Operation timed out` y `http=000`.

> [!WARNING]
> Si cierras la terminal en medio de la pausa, el contenedor se queda congelado y el resto de órdenes no responden. El paso 21 lo suelta. Si sales antes: `docker unpause vault-dev`.

### 21 — Reanuda y lee otra vez

**Acción:**

```bash
docker unpause vault-dev
/tmp/app-pagos.sh
```

**Por qué:** al quitar la pausa la memoria sigue. La aplicación vuelve a leer la misma clave.

**Resultado esperado:** `http=200` y `clave-viva`.

![Con el contenedor en pausa, curl agota el tiempo (http=000); al reanudar, http=200 y clave-viva](../img/M06-01-pausa.png)

## Comprueba tu entendimiento

**Login malo, sin llegar al secreto**
`SECRET_ID=no-vale /tmp/app-pagos.sh`
→ El script falla en el login, antes de imprimir `http=200`. Python lanza `KeyError: 'auth'` porque la respuesta no trae `client_token`. No es un 404 del secreto.

![secret_id inválido: el script falla en el login, sin http=200](../img/M06-01-login-mal.png)

## Reto

### 1 — Checklist de un caso

Elige el paso 10 y escribe en tres líneas: preparación, acción, resultado que afirmas. Sin mirar el JSON, tiene que poder corregirlo otra persona.

<details>
<summary>Ver solución</summary>

Preparación: rol AppRole con policy que solo lee `secret/data/nominas/api`, secreto `secret/pagos/api` existente.
Acción: login de ese rol y GET de `secret/data/pagos/api`.
Resultado: HTTP 403, texto `permission denied`, y con el token `root` la clave sigue siendo la que había.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| El caso feliz ya es 403 `invalid token` | Quedó `APP_TOKEN` de otro ejercicio en esta terminal | `unset APP_TOKEN` y vuelve a lanzar el paso 6 |
| Todos los pasos dan 400 en el login | `ROLE_ID` o `SECRET_ID` son del rol anterior | Vuelve a exportarlos, como al principio del paso 12 |
| El paso 8 sigue en 200 tras el `sleep` | El TTL no se aplicó (`explicit-max-ttl` ausente) o no esperaste | Repite el paso 7 y el `sleep 6` |
| Tras el paso 20 no responde nada | El contenedor sigue en pausa | `docker unpause vault-dev` |
| 403 en el secreto inexistente | Sigues con el rol `sin-pagos` | El `export` del paso 12 tiene que ser el rol `pagos` |
