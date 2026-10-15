# El job que falla cerrado

[← Página anterior](01-lab-consumo-automatico.md) · [Siguiente página →](03-lab-agent-en-caliente.md)

El inyector de la página anterior entra en Vault, exporta `CLAVE` y ejecuta el proceso de negocio. Un job de CI es ese inyector, con una exigencia más: el test afirma el fallo por el código de salida. Vas a escribir el job para que salga con un código distinto en cada caso y no imprima la clave cuando no entró. Aquí el job imprime la clave él mismo, para que la salida sea una sola línea comprobable.

### Objetivo

`/tmp/ci-pagos.sh` imprime `clave-pagos` y sale 0 con credenciales buenas; sale 2 si faltan; sale 1 e imprime `login=400` si el `secret_id` no vale, sin imprimir la clave.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
unset ROLE_ID SECRET_ID
```

Servidor vacío. El script se crea en esta página.

### En qué consiste

Preparar el secreto y el rol comando a comando, escribir el job y lanzarlo tres veces. No arranques Vault Agent aquí.

### 1 — Guarda la clave

**Acción:**

```bash
vault kv put secret/pagos/api clave=clave-pagos
```

**Por qué:** es el valor que el job imprime cuando el login sale bien.

**Resultado esperado:** la metadata muestra `version` `1`.

### 2 — Registra la policy

**Acción:**

```bash
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
```

**Por qué:** el token del job solo podrá leer ese camino.

**Resultado esperado:** `Policy solo-pagos escrita.`

### 3 — Habilita AppRole

**Acción:**

```bash
vault auth enable approle
```

**Por qué:** el job entra como una aplicación, no con el token `root`.

**Resultado esperado:** `Success! Enabled approle auth method at: approle/`

### 4 — Crea el rol

**Acción:**

```bash
vault write auth/approle/role/pagos \
  token_policies=solo-pagos \
  token_ttl=15m \
  token_max_ttl=1h
```

**Por qué:** el rol entrega un token con la policy `solo-pagos`.

**Resultado esperado:** `Success! Data written to: auth/approle/role/pagos`

### 5 — Guarda los identificadores del job

**Acción:**

```bash
export ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
export SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** el script solo verá estas dos variables, como un job al que el sistema de CI se las inyecta. `export` las deja en esta terminal. El script no usa `VAULT_TOKEN`.

**Resultado esperado:** las dos longitudes son mayores que 10.

### 6 — Escribe el script

**Acción:**

```bash
cat > /tmp/ci-pagos.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${ROLE_ID:-}" || -z "${SECRET_ID:-}" ]]; then
  echo "login=sin-credenciales"
  exit 2
fi
body=$(mktemp)
code=$(curl -sS -o "$body" -w "%{http_code}" --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login")
if [[ "$code" != "200" ]]; then
  echo "login=${code}"
  rm -f "$body"
  exit 1
fi
token=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])' < "$body")
rm -f "$body"
curl -sS --header "X-Vault-Token: ${token}" \
  "${VAULT_ADDR}/v1/secret/data/pagos/api" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"]["clave"])'
EOF
chmod +x /tmp/ci-pagos.sh
```

**Por qué:** si el login no es 200, el script no busca `client_token` y por tanto no revienta con un `KeyError` difícil de afirmar. Sale 1 y deja el HTTP en una línea. Si faltan variables, ni siquiera llama a Vault: el fallo es del job, no del servidor.

**Resultado esperado:** el fichero existe. Todavía no ha impreso la clave.

> [!TIP]
> El `mktemp` guarda el cuerpo fuera de la pantalla. Así un login 400 no se mezcla con la línea `login=400` que el test va a comparar.

### 7 — Caso feliz

**Acción:**

```bash
/tmp/ci-pagos.sh
echo "exit=$?"
```

**Por qué:** es la línea base. Sin este 0, el `exit=1` del `secret_id` inválido podría ser un script roto.

**Resultado esperado:** `clave-pagos` y `exit=0`.

![El job imprime la clave y sale 0](../img/M05-02-ok.png)

### 8 — Sin credenciales

**Acción:**

```bash
ROLE_ID= SECRET_ID= /tmp/ci-pagos.sh || echo "exit=$?"
```

**Por qué:** el prefijo `ROLE_ID= SECRET_ID=` vacía las variables solo para esta ejecución. Tu shell sigue teniendo los valores buenos. El job tiene que decir que ni lo intentó.

**Resultado esperado:** `login=sin-credenciales` y `exit=2`. No aparece `clave-pagos`.

![Sin ROLE_ID ni SECRET_ID el job sale 2 y no llama a la clave](../img/M05-02-vacio.png)

### 9 — secret_id que no vale

**Acción:**

```bash
SECRET_ID=00000000-0000-0000-0000-000000000000 /tmp/ci-pagos.sh || echo "exit=$?"
```

**Por qué:** aquí sí hay llamada a Vault. El login responde 400 y el script se detiene antes de leer `secret/pagos/api`. La clave no debe salir en la misma ejecución: si saliera, el test no podría usar «imprimió la clave» como señal de éxito.

**Resultado esperado:** `login=400` y `exit=1`. No aparece `clave-pagos`.

![secret_id inválido: login=400 y salida 1, sin la clave](../img/M05-02-400.png)

## Comprueba tu entendimiento

**Las variables buenas siguen en la terminal**
`/tmp/ci-pagos.sh`
→ Otra vez `clave-pagos`. Los prefijos de las dos ejecuciones anteriores no las borraron.

## Reto

### 1 — Falta solo una de las dos

Ejecuta el script con `SECRET_ID` vacío y `ROLE_ID` el bueno.

<details>
<summary>Ver solución</summary>

```bash
SECRET_ID= /tmp/ci-pagos.sh || echo "exit=$?"
```

`login=sin-credenciales` y `exit=2`. Con una sola credencial el script no intenta el login.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| El caso feliz imprime `login=sin-credenciales` | No exportaste `ROLE_ID` y `SECRET_ID` | Repite las dos líneas `export` |
| `exit=1` y un traceback de Python | El script no es el de esta página (busca `client_token` sin mirar el HTTP) | Vuelve a escribir `/tmp/ci-pagos.sh` |
| El `secret_id` inválido imprime la clave | El prefijo no se aplicó y usó el `SECRET_ID` bueno | La orden es `SECRET_ID=00000000-0000-0000-0000-000000000000 /tmp/ci-pagos.sh` |
