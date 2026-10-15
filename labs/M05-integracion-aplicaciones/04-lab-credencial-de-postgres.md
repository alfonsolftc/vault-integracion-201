# La app entra en Postgres

[← Página anterior](03-lab-agent-en-caliente.md) · [Siguiente página →](../M06-testing-integraciones/README.md)

La clave del KV es un valor que alguien guardó. Un usuario de base de datos puede crearlo Vault en el momento en que la app lo pide, con caducidad, y borrarlo al revocar el lease. Vas a dejar Postgres al lado de Vault y una app que entra con ese usuario, lee una fila y lo dice.

```text
tu terminal                     vault-dev                         pagos-db
app-pagos-db.sh                 motor database                    Postgres
    |  login y GET de credenciales   |                                  |
    +------------------------------->|  CREATE ROLE usuario temporal    |
    |  usuario y contraseña          +--------------------------------->|
    |  psql con ese usuario, por la red                                 |
    +------------------------------------------------------------------>|
```

La contraseña de `vaultadmin` la usa Vault para poder crear usuarios. La app no la ve. Cada GET a `database/creds/lectura` crea un usuario distinto. Al revocar el lease, ese usuario deja de existir.

### Objetivo

`/tmp/app-pagos-db.sh` imprime `Hola, soy la app de pagos y estoy usando el usuario v-approle-lectura-…` y la línea `pedido: pendiente`. Una segunda ejecución muestra otro usuario. Tras revocar el lease, ese usuario ya no está en `pg_roles` y el `psql` de la app falla.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. Postgres se crea en esta página con la imagen `postgres:16-alpine`. La primera vez Docker descarga la imagen.

### En qué consiste

Dejar Postgres en la red de Vault, comando a comando. Enseñar al motor `database` a crear usuarios. Ejecutar la app dos veces. Revocar el lease y ver que el usuario ya no está.

### 1 — Quita un Postgres anterior

**Acción:**

```bash
docker rm -f pagos-db >/dev/null 2>&1 || true
```

**Por qué:** libera el nombre `pagos-db` si quedó de otro intento. Si no existía, la orden sigue.

**Resultado esperado:** termina sin error.

### 2 — Anota la red de Vault

**Acción:**

```bash
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
```

**Por qué:** Vault tiene que llegar a Postgres por el nombre `pagos-db`. Guardas en `RED` la red de `vault-dev` para crear la base ahí.

**Resultado esperado:** `red=infra_default`.

### 3 — Arranca Postgres

**Acción:**

```bash
docker run -d --name pagos-db --network "$RED" \
  -e POSTGRES_USER=vaultadmin \
  -e POSTGRES_PASSWORD=vaultadmin-lab \
  -e POSTGRES_DB=pagos \
  postgres:16-alpine
```

**Por qué:** `pagos-db` es la base, no el servidor Vault. `vaultadmin` y `vaultadmin-lab` son el administrador con el que tú creas la tabla y con el que Vault creará los usuarios de la app. La app no usa esa contraseña.

**Resultado esperado:** `docker run` imprime un id. La primera vez descarga la imagen y puede tardar un minuto.

> [!TIP]
> La descarga ocurre dentro de este `docker run`, antes de que el contenedor exista. El paso siguiente espera a que acepte conexiones.

### 4 — Espera a que acepte conexiones

**Acción:**

```bash
for _i in $(seq 1 30); do
  docker exec pagos-db pg_isready -U vaultadmin -d pagos >/dev/null 2>&1 && break
  sleep 1
done
docker exec pagos-db pg_isready -U vaultadmin -d pagos
```

**Por qué:** el bucle reintenta hasta 30 segundos. El `pg_isready` final te enseña el estado, sin esconderlo.

**Resultado esperado:** una línea con `accepting connections`.

### 5 — Crea la tabla del pedido

**Acción:**

```bash
docker exec pagos-db psql -U vaultadmin -d pagos -c \
  "CREATE TABLE pedidos (id int PRIMARY KEY, estado text); INSERT INTO pedidos VALUES (1, 'pendiente');"
```

**Por qué:** `pedidos` es lo único que la app va a leer. Este `psql` entra como administrador del laboratorio, por el socket del contenedor. La app no entra por aquí.

**Resultado esperado:** `CREATE TABLE` e `INSERT 0 1`.

### 6 — Habilita el motor database

**Acción:**

```bash
vault secrets enable database
```

**Por qué:** este motor no guarda la clave: habla con Postgres y crea usuarios. En el servidor recién reiniciado no está habilitado.

**Resultado esperado:** `Success! Enabled the database secrets engine at: database/`

### 7 — Enseña a Vault cómo conectar

**Acción:**

```bash
vault write database/config/pagos \
  plugin_name=postgresql-database-plugin \
  allowed_roles=lectura \
  connection_url="postgresql://{{username}}:{{password}}@pagos-db:5432/pagos?sslmode=disable" \
  username="vaultadmin" \
  password="vaultadmin-lab"
```

**Por qué:** `database/config/pagos` es la conexión de administrador. Vault guarda `vaultadmin-lab` y la usa para hacer `CREATE ROLE`. `pagos-db` es el nombre del contenedor en la red. `allowed_roles=lectura` es la lista de roles de este motor que esa conexión acepta crear.

**Resultado esperado:** `Success! Data written to: database/config/pagos`

### 8 — Define el rol que crea usuarios

**Acción:**

```bash
vault write database/roles/lectura \
  db_name=pagos \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  creation_statements="GRANT SELECT ON TABLE pedidos TO \"{{name}}\";" \
  revocation_statements="REVOKE ALL PRIVILEGES ON TABLE pedidos FROM \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl=1h \
  max_ttl=24h
```

**Por qué:** cada petición rellena `{{name}}`, `{{password}}` y `{{expiration}}`. La primera sentencia crea el usuario. La segunda le deja leer `pedidos` y nada más. Al revocar, Vault ejecuta el `DROP ROLE`. El TTL por defecto es una hora.

**Resultado esperado:** `Success! Data written to: database/roles/lectura`

### 9 — Policy de la app

**Acción:**

```bash
bash infra/policy.sh lee-postgres <<'EOF'
path "database/creds/lectura" {
  capabilities = ["read"]
}
EOF
```

**Por qué:** el GET a `database/creds/lectura` es el que crea el usuario. La contraseña de `vaultadmin` está en `database/config/pagos`, y esta policy no nombra ese camino.

**Resultado esperado:** `Policy lee-postgres escrita.`

### 10 — Habilita AppRole

**Acción:**

```bash
vault auth enable approle
```

**Por qué:** la app entra con AppRole, igual que en el KV.

**Resultado esperado:** `Success! Enabled approle auth method at: approle/`

### 11 — Crea el rol pagos

**Acción:**

```bash
vault write auth/approle/role/pagos \
  token_policies=lee-postgres \
  token_ttl=15m \
  token_max_ttl=1h
```

**Por qué:** el rol queda atado a la policy `lee-postgres`. El token que reciba la app solo podrá pedir credenciales de Postgres.

**Resultado esperado:** `Success! Data written to: auth/approle/role/pagos`

### 12 — Guarda role_id y secret_id

**Acción:**

```bash
export ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** el script de la app hereda estas dos variables. No hereda la contraseña de `vaultadmin`.

**Resultado esperado:** `role_len=36 secret_len=36`.

### 13 — Escribe la app

**Acción:**

```bash
cat > /tmp/app-pagos-db.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
login=$(curl -sS --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login")
token=$(printf '%s' "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')
creds=$(curl -sS --header "X-Vault-Token: ${token}" \
  "${VAULT_ADDR}/v1/database/creds/lectura")
user=$(printf '%s' "$creds" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["username"])')
pass=$(printf '%s' "$creds" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["password"])')
lease=$(printf '%s' "$creds" | python3 -c 'import json,sys; print(json.load(sys.stdin)["lease_id"])')
red=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' pagos-db | head -n 1)
estado=$(docker run --rm --network "$red" -e PGPASSWORD="$pass" postgres:16-alpine \
  psql -h pagos-db -U "$user" -d pagos -tA -c "SELECT estado FROM pedidos WHERE id = 1")
echo "Hola, soy la app de pagos y estoy usando el usuario ${user}"
echo "pedido: ${estado}"
printf '%s\n' "$user" > /tmp/pg-user
printf '%s\n' "$pass" > /tmp/pg-pass
printf '%s\n' "$lease" > /tmp/pg-lease
EOF
chmod +x /tmp/app-pagos-db.sh
```

**Por qué:** un solo GET devuelve usuario, contraseña y `lease_id`. Las tres lecturas de Python parten de esa misma respuesta: un segundo GET crearía otro usuario. El `docker run` es el cliente `psql`: entra a `pagos-db` por la red, con el usuario que Vault acaba de crear. Los tres ficheros de `/tmp` guardan esa credencial para revocarla después.

**Resultado esperado:** el fichero existe y es ejecutable. Todavía no ha impreso el usuario.

### 14 — Primera ejecución

**Acción:**

```bash
/tmp/app-pagos-db.sh | tee /tmp/pg-1.txt
```

**Por qué:** la app pide un usuario, entra y lee la fila. `tee` guarda la salida para compararla con la siguiente.

**Resultado esperado:** una línea `Hola, soy la app de pagos y estoy usando el usuario v-approle-lectura-` seguida de un sufijo, y otra línea `pedido: pendiente`.

![La app entra en Postgres con el usuario que Vault acaba de crear](../img/M05-04-app.png)

### 15 — Segunda ejecución

**Acción:**

```bash
/tmp/app-pagos-db.sh | tee /tmp/pg-2.txt
```

**Por qué:** cada GET crea un usuario distinto. `/tmp/pg-user` queda con el de esta ejecución, que es el que vas a revocar. La fila leída es la misma.

**Resultado esperado:** la misma forma de salida, con otro sufijo en el usuario, y `pedido: pendiente`.

![La segunda ejecución recibe otro usuario y lee la misma fila](../img/M05-04-otro.png)

### 16 — Revoca el lease

**Acción:**

```bash
vault lease revoke "$(cat /tmp/pg-lease)"
```

**Por qué:** esta orden ejecuta el `DROP ROLE` del rol `lectura`. Vault responde que la operación queda encolada. El fichero `/tmp/pg-lease` es el de la última ejecución.

**Resultado esperado:** `All revocation operations queued successfully!`

### 17 — Espera a que el DROP termine

**Acción:**

```bash
sleep 2
```

**Por qué:** dos segundos dejan que la revocación encolada ejecute el `DROP` antes de mirar el catálogo.

**Resultado esperado:** el comando termina. No imprime el usuario.

### 18 — Mira si el usuario sigue en el catálogo

**Acción:**

```bash
docker exec pagos-db psql -U vaultadmin -d pagos -tA -c \
  "SELECT count(*) FROM pg_roles WHERE rolname = '$(cat /tmp/pg-user)'"
```

**Por qué:** preguntas a Postgres, como administrador, si ese rol existe. Esta consulta es la prueba del `DROP`.

**Resultado esperado:** una línea `0`.

### 19 — Anota otra vez la red

**Acción:**

```bash
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' pagos-db | head -n 1)
echo "red=$RED"
```

**Por qué:** el cliente `psql` tiene que salir a la misma red que `pagos-db`. Si cambiaste de terminal, `RED` ya no está; esta lectura la recupera.

**Resultado esperado:** `red=infra_default`.

### 20 — La app ya no puede entrar con ese usuario

**Acción:**

```bash
docker run --rm --network "$RED" -e PGPASSWORD="$(cat /tmp/pg-pass)" postgres:16-alpine \
  psql -h pagos-db -U "$(cat /tmp/pg-user)" -d pagos -tA \
  -c "SELECT estado FROM pedidos WHERE id = 1" || echo "psql_exit=$?"
```

**Por qué:** este `psql` usa el usuario y la contraseña de la última ejecución, por la red. Postgres contesta `password authentication failed` tanto si la contraseña es mala como si el usuario ya no existe: el mensaje no distingue. El `0` del catálogo es lo que afirma el `DROP`.

**Resultado esperado:** `FATAL:  password authentication failed for user "v-approle-lectura-…"` y `psql_exit=2`. No aparece `pedido: pendiente`.

![Tras revocar el lease, Postgres ya no tiene ese usuario](../img/M05-04-revoke.png)

### 21 — Quita Postgres

**Acción:**

```bash
docker rm -f pagos-db >/dev/null
```

**Por qué:** el ejercicio ha terminado. El contenedor de la base no hace falta para el módulo siguiente.

**Resultado esperado:** termina sin imprimir el pedido.

## Comprueba tu entendimiento

**La app no conoce al administrador**
`grep vaultadmin /tmp/app-pagos-db.sh || echo "sin vaultadmin"`
→ `sin vaultadmin`. La contraseña `vaultadmin-lab` está en la config del motor, no en la app.

## Reto

### 1 — El token de la app no lee la config

Crea un token con la policy `lee-postgres` y pide `database/config/pagos`.

<details>
<summary>Ver solución</summary>

```bash
TOK=$(vault token create -policy=lee-postgres -ttl=5m -field=token)
curl -sS -o /tmp/cfg-body -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${TOK}" \
  "${VAULT_ADDR}/v1/database/config/pagos"
```

`http=403`. El cuerpo lleva `permission denied`. La policy solo nombra `database/creds/lectura`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `is not an allowed role` | `allowed_roles` no incluye `lectura` | Repite el `vault write database/config/pagos` |
| En la primera ejecución, `password authentication failed` | Usuario y contraseña salen de dos GET distintos. Cada lectura crea un usuario nuevo | Deja un solo `curl` a `database/creds/lectura`. Tras revocar, ese mismo mensaje es el resultado esperado |
| `relation "pedidos" does not exist` | La tabla no se creó | Repite el `psql` que hace `CREATE TABLE` |
| `permission denied` al hacer `SELECT` | Falta el `GRANT` del rol | Repite el `vault write database/roles/lectura` |
| `pg_isready` no acaba en accepting | Postgres sigue arrancando, o la imagen aún se descarga | Espera y vuelve a lanzar el bucle |
| `already exists` al crear la tabla | `pagos-db` es de una ejecución anterior | Empieza otra vez por `docker rm -f pagos-db` |
| El `count(*)` sale `1` | El `DROP` aún no se ha ejecutado | Espera otros dos segundos y repite la consulta |
