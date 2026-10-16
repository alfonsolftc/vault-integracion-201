# SSH con Vault como CA

[← Página anterior](03-lab-firma-transit.md) · [Siguiente página →](05-lab-bateria.md)

La aplicación de pagos necesita entrar por SSH. No reparte una contraseña ni una clave privada larga. Vault hace de CA del motor `ssh`: firma la clave pública del cliente y el certificado lleva el principal `pagos`. La clave privada de la CA no sale de Vault. La del cliente no se imprime.

### Objetivo

Un certificado de usuario firmado por Vault, con principal `pagos`, y la prueba de que pedir el principal `root` responde 400. La lectura de `ssh/config/ca` solo trae `public_key`.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. Hace falta `ssh-keygen` en esta terminal (paquete `openssh-client`). Si no está:

```bash
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client
```

### En qué consiste

Habilitar el motor SSH, generar la CA, crear el rol y la policy, generar un par de claves en esta máquina, firmar la pública con AppRole y afirmar el certificado. No arranca un `sshd`: la prueba es el contrato del certificado.

### 1 — Habilita el motor SSH

**Acción:**

```bash
vault secrets enable -path=ssh ssh
```

**Por qué:** el motor `ssh` en modo CA firma claves OpenSSH. No es el motor `pki` de certificados X.509: aquí el formato es el de `ssh-keygen -L`.

**Resultado esperado:** `Success! Enabled the ssh secrets engine at: ssh/`.

### 2 — Genera la CA dentro de Vault

**Acción:**

```bash
vault write ssh/config/ca generate_signing_key=true
```

**Por qué:** Vault crea el par de la CA. La respuesta muestra la `public_key`. La privada se queda en el servidor.

**Resultado esperado:** una línea `public_key` que empieza por `ssh-rsa`.

### 3 — Guarda la clave pública de la CA

**Acción:**

```bash
vault read -field=public_key ssh/config/ca > /tmp/vault-ssh-ca.pub
ssh-keygen -lf /tmp/vault-ssh-ca.pub
vault read -format=json ssh/config/ca \
  | python3 -c 'import json,sys; print("campos", sorted(json.load(sys.stdin)["data"].keys()))'
```

**Por qué:** el fichero de la CA pública es lo que un `sshd` pondría en `TrustedUserCAKeys`. La lista de campos confirma que no hay `private_key` en la lectura.

**Resultado esperado:** una huella `4096 SHA256:… (RSA)` y `campos ['public_key']`.

![La CA pública tiene huella SHA256 y la lectura solo trae public_key](../img/M07-04-ca.png)

### 4 — Crea el rol de firma

**Acción:**

```bash
vault write ssh/roles/pagos-ssh \
  key_type=ca \
  allow_user_certificates=true \
  allowed_users=pagos \
  default_user=pagos \
  ttl=5m \
  max_ttl=30m
```

**Por qué:** `key_type=ca` firma certificados de usuario. `allowed_users=pagos` es el único principal que este rol puede poner en el certificado. El TTL corto es el de la sesión SSH en un entorno real.

**Resultado esperado:** `Success! Data written to: ssh/roles/pagos-ssh`.

### 5 — Policy y AppRole que solo firman

**Acción:**

```bash
bash infra/policy.sh firma-ssh <<'EOF'
path "ssh/sign/pagos-ssh" {
  capabilities = ["create", "update"]
}
EOF
vault auth enable approle
vault write auth/approle/role/ssh-pagos \
  token_policies=firma-ssh \
  token_ttl=15m \
  token_max_ttl=1h
ROLE_ID=$(vault read -field=role_id auth/approle/role/ssh-pagos/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/ssh-pagos/secret-id)
export ROLE_ID SECRET_ID
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

**Por qué:** la aplicación no usa el token `root`. Solo puede llamar a `ssh/sign/pagos-ssh`. No lee KV ni exporta la CA.

**Resultado esperado:** `Policy firma-ssh escrita.`, el alta de AppRole, `Success! Data written to: auth/approle/role/ssh-pagos` y `role_len=36 secret_len=36`.

### 6 — Genera el par del cliente

**Acción:**

```bash
rm -f /tmp/pagos-ssh /tmp/pagos-ssh.pub /tmp/pagos-ssh-cert.pub
ssh-keygen -t ed25519 -N '' -f /tmp/pagos-ssh -C 'pagos@lab' -q
stat -c 'modo=%a bytes=%s' /tmp/pagos-ssh
wc -c < /tmp/pagos-ssh.pub | awk '{print "pub_bytes="$1}'
```

**Por qué:** la clave privada nace en esta máquina, con modo `600`. Vault solo va a ver la pública. No hagas `cat` del fichero privado.

**Resultado esperado:** `modo=600` y un `pub_bytes` pequeño (alrededor de 90).

> [!WARNING]
> Si usas la función `vault` de `entorno.sh`, el CLI corre dentro de `vault-dev`. No uses `public_key=@/tmp/…`: ese camino se mira dentro del contenedor. Pasa el contenido con una variable, como en el paso 8.

### 7 — Entra con AppRole

**Acción:**

```bash
APP_TOKEN=$(curl -sS --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')
echo "token_len=${#APP_TOKEN}"
```

**Por qué:** el token de la app firma el certificado. No se imprime el valor, solo la longitud.

**Resultado esperado:** `token_len=` con un entero mayor que 0 (en este laboratorio, cerca de 95).

### 8 — Firma la clave pública

**Acción:**

```bash
export PUB="$(cat /tmp/pagos-ssh.pub)"
curl -sS -o /tmp/ssh-sign.json -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${APP_TOKEN}" \
  --request POST \
  --data "$(python3 -c 'import json,os; print(json.dumps({"public_key": os.environ["PUB"], "valid_principals": "pagos"}))')" \
  "${VAULT_ADDR}/v1/ssh/sign/pagos-ssh"
python3 -c 'import json; d=json.load(open("/tmp/ssh-sign.json")); open("/tmp/pagos-ssh-cert.pub","w").write(d["data"]["signed_key"]); print("cert_bytes", len(d["data"]["signed_key"]))'
```

**Por qué:** Vault recibe solo la pública y el principal. Devuelve un certificado OpenSSH, no una clave privada nueva. El fichero `*-cert.pub` es lo que el cliente presenta junto a `/tmp/pagos-ssh`.

**Resultado esperado:** `http=200` y `cert_bytes` por encima de 500.

### 9 — Afirma el certificado

**Acción:**

```bash
ssh-keygen -L -f /tmp/pagos-ssh-cert.pub
```

**Por qué:** esta es la prueba de integración. Tipo de certificado de usuario, principal `pagos`, CA de firma presente y ventana `Valid` de unos cinco minutos. No hace falta un servidor SSH para afirmar el contrato.

**Resultado esperado:** en la salida aparecen:

- `Type: ssh-ed25519-cert-v01@openssh.com user certificate`
- `Signing CA: RSA SHA256:…`
- `Principals:` y debajo `pagos`
- `Valid: from … to …` con un margen de cinco minutos

![El certificado es de usuario, principal pagos, firmado por la CA de Vault](../img/M07-04-cert.png)

### 10 — Un principal no permitido

**Acción:**

```bash
export PUB="$(cat /tmp/pagos-ssh.pub)"
curl -sS -o /tmp/ssh-root.json -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${APP_TOKEN}" \
  --request POST \
  --data "$(python3 -c 'import json,os; print(json.dumps({"public_key": os.environ["PUB"], "valid_principals": "root"}))')" \
  "${VAULT_ADDR}/v1/ssh/sign/pagos-ssh"
python3 -c 'import json; print(json.load(open("/tmp/ssh-root.json")).get("errors"))'
```

**Por qué:** el rol solo admite `pagos`. Pedir `root` es el fallo que el test de autorización tiene que ver: 400, no un certificado con otro principal.

**Resultado esperado:** `http=400` y un error que menciona que `root` no es un valor válido para `valid_principals`.

![Pedir el principal root responde 400](../img/M07-04-root.png)

## Comprueba tu entendimiento

**La privada del cliente no viajó a Vault**
`grep -c PRIVATE /tmp/pagos-ssh-cert.pub; grep -c BEGIN /tmp/pagos-ssh`
→ El certificado imprime `0`. La clave privada sigue en `/tmp/pagos-ssh` (modo 600) y no se ha volcado en la respuesta de firma.

## Reto

### 1 — Afirmar el principal sin mirar el bloque entero

Con el certificado ya en `/tmp/pagos-ssh-cert.pub`, imprime una sola línea `ASSERT principal=pagos` si el principal es exactamente ese.

<details>
<summary>Ver solución</summary>

```bash
python3 - <<'PY'
import subprocess
out = subprocess.check_output(["ssh-keygen", "-L", "-f", "/tmp/pagos-ssh-cert.pub"], text=True)
lines = out.splitlines()
principals = []
catch = False
for line in lines:
    if line.strip().startswith("Principals:"):
        catch = True
        continue
    if catch:
        if line.startswith("\t") or line.startswith(" "):
            principals.append(line.strip())
        else:
            break
print("ASSERT principal=pagos" if principals == ["pagos"] else "ASSERT no")
PY
```

`ASSERT principal=pagos`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `ssh-keygen: command not found` | Falta `openssh-client` | El `apt-get` del punto de partida |
| `error reading file: open /tmp/…` con `@/tmp/…` | El CLI `vault` corre dentro de `vault-dev` | Usa `PUB=$(cat …)` y la variable, como en el paso 8 |
| `http=403` al firmar | El token no es el de `ssh-pagos` o la policy no tiene `ssh/sign/pagos-ssh` | Repite los pasos 5 y 7 |
| El certificado no lista `pagos` | Firmaste sin `valid_principals` o con otro valor | Repite el paso 8 con `"valid_principals": "pagos"` |
| `root is not a valid value` en el paso 8 | Estás en el cuerpo del paso 10 | El 400 de `root` es el resultado bueno del paso 10 |
