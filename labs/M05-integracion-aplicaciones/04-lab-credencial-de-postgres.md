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

Servidor vacío. Postgres se crea en el paso 1 con la imagen `postgres:16-alpine`. La primera vez Docker descarga la imagen.

### En qué consiste

Dejar Postgres con una tabla, enseñar a Vault a crear usuarios de esa base, y ejecutar la app dos veces. Después, revocar el lease y ver que el usuario ya no entra.

### 1 — Postgres en la red de Vault

**Acción:**

```bash
docker rm -f pagos-db >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
docker run -d --name pagos-db --network "$RED" \
  -e POSTGRES_USER=vaultadmin \
  -e POSTGRES_PASSWORD=vaultadmin-lab \
  -e POSTGRES_DB=pagos \
  postgres:16-alpine
for _i in $(seq 1 30); do
  docker exec pagos-db pg_isready -U vaultadmin -d pagos >/dev/null 2>&1 && break
  sleep 1
done
docker exec pagos-db pg_isready -U vaultadmin -d pagos
docker exec pagos-db psql -U vaultadmin -d pagos -c \
  "CREATE TABLE pedidos (id int PRIMARY KEY, estado text); INSERT INTO pedidos VALUES (1, 'pendiente');"
```

**Por qué:** `pagos-db` es la base, no el servidor Vault. Comparte la red de `vault-dev` para que el motor `database` pueda conectarse por el nombre `pagos-db`. La tabla `pedidos` es lo único que la app va a leer. `vaultadmin` es el usuario con el que tú creas la tabla y con el que Vault creará los usuarios de la app. La app no lo usa.

**Resultado esperado:** `pg_isready` imprime `accepting connections`. El `psql` termina con `CREATE TABLE` e `INSERT 0 1`.

> [!TIP]
> La primera `docker run` descarga `postgres:16-alpine`. Puede tardar un minuto. El bucle de `pg_isready` empieza cuando el contenedor ya existe.

### 2 — Motor database, conexión y rol

**Acción:**

```bash
vault secrets enable database
vault write database/config/pagos \
  plugin_name=postgresql-database-plugin \
  allowed_roles=lectura \
  connection_url="postgresql://{{username}}:{{password}}@pagos-db:5432/pagos?sslmode=disable" \
  username="vaultadmin" \
  password="vaultadmin-lab"
vault write database/roles/lectura \
  db_name=pagos \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  creation_statements="GRANT SELECT ON TABLE pedidos TO \"{{name}}\";" \
  revocation_statements="REVOKE ALL PRIVILEGES ON TABLE pedidos FROM \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl=1h \
  max_ttl=24h
```

**Por qué:** `database/config/pagos` es la conexión de administrador. Vault guarda ahí `vaultadmin-lab` y la usa para hacer `CREATE ROLE`. `allowed_roles=lectura` es la lista de roles de este motor que esa conexión acepta crear. `{{name}}`, `{{password}}` y `{{expiration}}` los rellena Vault en cada petición. El `GRANT` deja a ese usuario leer `pedidos` y nada más. Al revocar, Vault ejecuta el `DROP ROLE`. El TTL por defecto es una hora: pasado ese tiempo el lease caduca y el usuario se borra igual.

**Resultado esperado:** tres líneas `Success!`. Una al habilitar `database/`, otra al escribir la config y otra al escribir el rol.

### 3 — Policy y AppRole de la app

**Acción:**

```bash
bash infra/policy.sh lee-postgres <<'EOF'
path "database/creds/lectura" {
  capabilities = ["read"]
}
EOF
vault auth enable approle
vault write auth/approle/role/pagos \
  token_policies=lee-postgres \
  token_ttl=15m \
  token_max_ttl=1h
export ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** la policy solo deja leer `database/creds/lectura`. Ese GET es el que crea el usuario. La config con la contraseña de `vaultadmin` está en `database/config/pagos`, y esta policy no la nombra. La app entra con AppRole, igual que en el KV.

**Resultado esperado:** `role_len=36 secret_len=36`.

### 4 — Escribe la app

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

**Por qué:** un solo GET devuelve usuario, contraseña y `lease_id`. Las tres lecturas de Python parten de esa misma respuesta. Un segundo GET crearía otro usuario y la contraseña ya no valdría para el primero. El `docker run` es el cliente `psql` de la app: entra a `pagos-db` por la red, con el usuario que Vault acaba de crear. Los tres ficheros de `/tmp` guardan esa credencial para el paso 6, donde se revoca.

**Resultado esperado:** el fichero existe y es ejecutable. Todavía no ha impreso el usuario.

### 5 — Ejecuta la app dos veces

**Acción:**

```bash
/tmp/app-pagos-db.sh | tee /tmp/pg-1.txt
/tmp/app-pagos-db.sh | tee /tmp/pg-2.txt
```

**Por qué:** cada ejecución pide credenciales nuevas. Las dos frases de saludo tienen que diferir en el usuario, y las dos leen la misma fila. `/tmp/pg-user` queda con el usuario de la segunda ejecución, que es el que vas a revocar.

**Resultado esperado:** cada ejecución imprime una línea `Hola, soy la app de pagos y estoy usando el usuario v-approle-lectura-` seguida de un sufijo distinto, y otra línea `pedido: pendiente`.

![La app entra en Postgres con el usuario que Vault acaba de crear](../img/M05-04-app.png)

![La segunda ejecución recibe otro usuario y lee la misma fila](../img/M05-04-otro.png)

### 6 — Revoca el lease

**Acción:**

```bash
vault lease revoke "$(cat /tmp/pg-lease)"
sleep 2
docker exec pagos-db psql -U vaultadmin -d pagos -tA -c \
  "SELECT count(*) FROM pg_roles WHERE rolname = '$(cat /tmp/pg-user)'"
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' pagos-db | head -n 1)
docker run --rm --network "$RED" -e PGPASSWORD="$(cat /tmp/pg-pass)" postgres:16-alpine \
  psql -h pagos-db -U "$(cat /tmp/pg-user)" -d pagos -tA \
  -c "SELECT estado FROM pedidos WHERE id = 1" || echo "psql_exit=$?"
docker rm -f pagos-db >/dev/null
```

**Por qué:** revocar ejecuta el `DROP ROLE` del paso 2. Vault responde que la operación queda encolada; los dos segundos dejan que ese `DROP` termine. El `count(*)` pregunta al catálogo, como administrador, si el usuario sigue ahí. El `psql` de después usa el usuario y la contraseña de la última ejecución. Por la red, Postgres contesta `password authentication failed` tanto si la contraseña es mala como si el usuario ya no existe: el mensaje no distingue. La prueba del `DROP` es el `0` del catálogo. El `docker rm` quita Postgres al cerrar el ejercicio.

**Resultado esperado:** `All revocation operations queued successfully!`, luego una línea `0`. El `psql` termina con `FATAL:  password authentication failed for user "v-approle-lectura-…"` y `psql_exit=2`. No aparece `pedido: pendiente`.

![Tras revocar el lease, Postgres ya no tiene ese usuario](../img/M05-04-revoke.png)

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

`http=403`. El cuerpo lleva `permission denied`. La policy del paso 3 solo nombra `database/creds/lectura`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `is not an allowed role` | `allowed_roles` no incluye `lectura` | Repite el `vault write database/config/pagos` del paso 2 |
| En el paso 5, `password authentication failed` | Usuario y contraseña salen de dos GET distintos. Cada lectura crea un usuario nuevo | Deja un solo `curl` a `database/creds/lectura`, como en el paso 4. En el paso 6 ese mismo mensaje es el resultado esperado |
| `relation "pedidos" does not exist` | La tabla no se creó | Repite el `psql` del paso 1 |
| `permission denied` al hacer `SELECT` | Falta el `GRANT` del rol | Repite el `vault write database/roles/lectura` |
| `pg_isready` no acaba en accepting | Postgres sigue arrancando, o la imagen aún se descarga | Espera y vuelve a lanzar el bucle del paso 1 |
| `already exists` al crear la tabla | `pagos-db` es de una ejecución anterior | El paso 1 empieza con `docker rm -f pagos-db` |
| El `count(*)` sale `1` | El `DROP` aún no se ha ejecutado | Espera otros dos segundos y repite la consulta |
