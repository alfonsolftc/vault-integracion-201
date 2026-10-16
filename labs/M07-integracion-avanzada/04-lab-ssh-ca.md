# Entrar por SSH

[← Página anterior](03-lab-firma-transit.md) · [Siguiente página →](05-lab-certificado-en-destino.md)

Vault administra quién entra en un servidor. El servidor es un Ubuntu que arrancas con Docker: tiene `sshd` y el usuario de sistema `ana`, y no tiene contraseña. `ana` entra en Vault con UserPass, Vault firma su clave y, desde esta terminal, `ssh` abre el puerto `2222` de `127.0.0.1`. Sin el certificado, `sshd` responde `Permission denied`. Pedir el principal `root` no produce certificado.

### Objetivo

`ssh -p 2222 ana@127.0.0.1` escribe `ana` y `acceso=ok`. Sin `'whoami; echo acceso=ok'`, la misma orden abre el tty de `ana`. Pedir el principal `root` responde `http=400`.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. El comando `vault` de esta terminal corre dentro de `vault-dev` cuando no hay CLI instalado en la máquina. El contenedor `destino` se crea en esta página. Quítalo al final: el comando está en el último paso.

### En qué consiste

Crear la CA en el motor `ssh`, levantar el Ubuntu publicando el puerto `2222`, firmar la clave de esta terminal con el token de `ana`, y conectar con `ssh` a `ana@127.0.0.1`.

### 1 — Habilita el motor y genera la CA

**Acción:**

```bash
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true key_type=ed25519
```

**Por qué:** el motor `ssh` en modo CA firma claves OpenSSH. No es el motor `pki` de certificados X.509. `key_type=ed25519` es la CA que acepta el `sshd` de Ubuntu 24.04. La respuesta muestra `public_key`. La privada se queda en Vault.

**Resultado esperado:** `Success! Enabled the ssh secrets engine at: ssh/`. En la ficha, `public_key` empieza por `ssh-ed25519`.

### 2 — Guarda la clave pública de la CA

**Acción:**

```bash
printf '%s\n' "$(vault read -field=public_key ssh/config/ca)" > /tmp/vault-ssh-ca.pub
ssh-keygen -lf /tmp/vault-ssh-ca.pub
vault read -format=json ssh/config/ca \
  | python3 -c 'import json,sys; print("campos", sorted(json.load(sys.stdin)["data"].keys()))'
```

**Por qué:** ese fichero es el que el servidor pondrá en `TrustedUserCAKeys`. La lista de campos confirma que la lectura no trae la privada. Si `ssh-keygen` no está en esta terminal: `sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client`.

**Resultado esperado:** una línea `256 SHA256:… (ED25519)` y `campos ['public_key']`. La huella cambia en cada arranque: Vault genera otra CA.

![La CA pública es ED25519 y la lectura solo trae public_key](../img/M07-04-ca.png)

### 3 — Crea el rol de acceso

**Acción:**

```bash
curl -sS -o /dev/null -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request POST \
  --data '{"key_type":"ca","allow_user_certificates":true,"allowed_users":"ana","default_user":"ana","allowed_extensions":"permit-pty","default_extensions":{"permit-pty":""},"ttl":"30m","max_ttl":"30m"}' \
  "${VAULT_ADDR}/v1/ssh/roles/acceso"
```

**Por qué:** el rol `acceso` solo puede firmar el principal `ana`. `permit-pty` permite el terminal. El certificado caduca a los treinta minutos. El cuerpo va en JSON porque `default_extensions` es un mapa: `vault write` con `clave=valor` lo manda como texto y Vault responde 400. El comando `vault` de este curso, además, corre dentro de `vault-dev` y no ve los ficheros de esta terminal.

**Resultado esperado:** `http=204`. Un 204 es el alta, sin cuerpo.

### 4 — Policy y UserPass de ana

**Acción:**

```bash
bash infra/policy.sh firma-ssh <<'EOF'
path "ssh/sign/acceso" {
  capabilities = ["create", "update"]
}
EOF
vault auth enable userpass
vault write auth/userpass/users/ana password=ana-lab policies=firma-ssh
```

**Por qué:** `ana` es una persona. Entra con usuario y contraseña, como en el módulo 4, y el token solo puede firmar en `ssh/sign/acceso`. No exporta la CA. El token `root` sigue en esta terminal para los pasos de administración.

**Resultado esperado:** `Policy firma-ssh escrita.`, `Success! Enabled userpass auth method at: userpass/` y `Success! Data written to: auth/userpass/users/ana`.

### 5 — Levanta el Ubuntu y arranca sshd

**Acción:**

```bash
docker rm -f destino >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
docker run -d --name destino -p 127.0.0.1:2222:22 --network "$RED" ubuntu:24.04 sleep infinity
docker exec destino bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq openssh-server >/tmp/apt.log 2>&1 && echo sshd=instalado'
docker cp /tmp/vault-ssh-ca.pub destino:/etc/ssh/vault-ca.pub
docker exec destino bash -c 'useradd -m -s /bin/bash ana && usermod -p "*" ana && mkdir -p /run/sshd && printf "%s\n" "TrustedUserCAKeys /etc/ssh/vault-ca.pub" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "PubkeyAuthentication yes" "UsePAM no" > /etc/ssh/sshd_config.d/vault.conf && ssh-keygen -A && /usr/sbin/sshd && ssh-keygen -lf /etc/ssh/vault-ca.pub && pgrep -a sshd && echo cuenta=ana'
```

**Por qué:** `destino` es la máquina a la que se entra. El `2222` de esta terminal es el `22` del Ubuntu: la sesión sale de aquí, no de `vault-dev`. Si el contenedor se crea otra vez sin este `-p` y sin el `sshd` de abajo, `ssh` recibe `Connection refused` o `Connection closed`. El Ubuntu no trae `sshd` y, al instalarlo, no lo arranca: el PID 1 es `sleep` y no hay systemd. `useradd` deja la cuenta bloqueada y entonces ignora el certificado (`account is locked`); `usermod -p "*"` abre la cuenta sin crear una contraseña. `TrustedUserCAKeys` apunta a la pública del paso 2.

**Resultado esperado:** `red=infra_default`, `sshd=instalado`, una línea `256 SHA256:… (ED25519)` con la misma huella del paso 2, una línea con `/usr/sbin/sshd` y `listener`, y `cuenta=ana`. La primera vez Docker descarga `ubuntu:24.04`.

### 6 — La clave de ana, en esta terminal

**Acción:**

```bash
rm -f /tmp/ana-ssh /tmp/ana-ssh.pub /tmp/ana-ssh-cert.pub
ssh-keygen -t ed25519 -N '' -f /tmp/ana-ssh -C 'ana@lab' -q
chmod 600 /tmp/ana-ssh
stat -c 'modo=%a' /tmp/ana-ssh
```

**Por qué:** la privada nace aquí. `ssh` no la usa si el modo es `644`: responde `UNPROTECTED PRIVATE KEY FILE` y `bad permissions`, y la ignora. `chmod 600` la deja solo para tu usuario. El certificado del paso siguiente tiene que llamarse `/tmp/ana-ssh-cert.pub`, al lado de `/tmp/ana-ssh`.

**Resultado esperado:** `modo=600`.

### 7 — Ana firma la pública

**Acción:**

```bash
curl -sS -o /tmp/ana.json -w "http=%{http_code}\n" --request POST \
  --data '{"password":"ana-lab"}' \
  "${VAULT_ADDR}/v1/auth/userpass/login/ana"
ANA=$(python3 -c 'import json; print(json.load(open("/tmp/ana.json"))["auth"]["client_token"])')
echo "token_len=${#ANA}"
export PUB="$(cat /tmp/ana-ssh.pub)"
curl -sS -o /tmp/ssh-sign.json -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${ANA}" \
  --request POST \
  --data "$(python3 -c 'import json,os; print(json.dumps({"public_key": os.environ["PUB"], "valid_principals": "ana"}))')" \
  "${VAULT_ADDR}/v1/ssh/sign/acceso"
python3 -c 'import json; d=json.load(open("/tmp/ssh-sign.json")); open("/tmp/ana-ssh-cert.pub","w").write(d["data"]["signed_key"]+"\n"); print("cert_bytes", len(d["data"]["signed_key"]))'
```

**Por qué:** el login es el de `ana` / `ana-lab`. El token que firma es el suyo, no el `root`. Vault recibe la pública de esta terminal y devuelve el certificado. La privada no sale de aquí. OpenSSH, en el paso 8, presenta `/tmp/ana-ssh-cert.pub` porque está junto a la clave.

**Resultado esperado:** el login es `http=200` y `token_len=95`. La firma es `http=200` y `cert_bytes` por encima de 500.

### 8 — Conecta desde esta terminal

**Acción:**

```bash
ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -p 2222 \
  ana@127.0.0.1 \
  'whoami; echo acceso=ok'
```

**Por qué:** esta es la conexión. `ssh` corre en esta terminal. `127.0.0.1` puerto `2222` es el `sshd` de `destino`. No hay contraseña: el servidor acepta el certificado porque está firmado por la CA de `TrustedUserCAKeys` y el principal es `ana`. Sin `'whoami; echo acceso=ok'`, la misma orden abre el tty. Se sale con `exit`.

**Resultado esperado:**

```text
ana
acceso=ok
```

![ssh a ana@127.0.0.1 por el puerto 2222 escribe ana y acceso=ok](../img/M07-04-cert.png)

### 9 — Un principal que el rol no firma

**Acción:**

```bash
export PUB="$(cat /tmp/ana-ssh.pub)"
curl -sS -o /tmp/ssh-root.json -w "http=%{http_code}\n" \
  --header "X-Vault-Token: ${ANA}" \
  --request POST \
  --data "$(python3 -c 'import json,os; print(json.dumps({"public_key": os.environ["PUB"], "valid_principals": "root"}))')" \
  "${VAULT_ADDR}/v1/ssh/sign/acceso"
python3 -c 'import json; print(json.load(open("/tmp/ssh-root.json")).get("errors"))'
```

**Por qué:** el rol solo admite `ana`. Pedir `root` no abre una sesión de administrador: Vault responde 400 y no hay certificado.

**Resultado esperado:** `http=400` y `['root is not a valid value for valid_principals']`.

![Pedir el principal root responde 400](../img/M07-04-root.png)

### 10 — Quita el servidor

**Acción:**

```bash
docker rm -f destino >/dev/null
```

**Por qué:** para `sshd` y libera el puerto `2222`. El servidor `vault-dev` sigue.

**Resultado esperado:** termina sin texto.

> [!WARNING]
> Si pasas a otra página sin este paso, `bash infra/reiniciar-vault.sh` también elimina `destino`.

## Comprueba tu entendimiento

**La privada de ana no viajó a Vault**

```bash
grep -c "BEGIN OPENSSH PRIVATE KEY" /tmp/ana-ssh
stat -c 'modo=%a' /tmp/ana-ssh
```

→ `1` y `modo=600`. Esa clave sigue en esta terminal. Vault solo recibió la pública para firmarla.

## Reto

### 1 — La clave sola no entra

Con `destino` todavía en marcha, aparta `/tmp/ana-ssh-cert.pub` y entra por el puerto `2222` solo con la privada.

<details>
<summary>Ver solución</summary>

```bash
mv /tmp/ana-ssh-cert.pub /tmp/ana-ssh-cert.bak
ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -o ConnectTimeout=5 \
  -p 2222 \
  ana@127.0.0.1 whoami || echo "salida=$?"
mv /tmp/ana-ssh-cert.bak /tmp/ana-ssh-cert.pub
```

`Permission denied (publickey).` y `salida=255`. Sin el fichero `-cert.pub`, OpenSSH presenta la clave sola y no hay `authorized_keys`. `sshd` solo fía de un certificado firmado por la CA. Al acabar: `docker rm -f destino`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `ssh-keygen: command not found` en el paso 2 | Falta `openssh-client` en esta terminal | El `apt-get` del paso 2 |
| `Connection refused` o `Connection closed` en el puerto 2222 | `destino` no publica el `2222`, o dentro no hay `sshd` | No basta `docker run`. Repite el paso 5 entero: el `-p`, el `apt` y `/usr/sbin/sshd` |
| `pgrep` no imprime nada | El paquete se instaló y `/usr/sbin/sshd` no llegó a lanzarse | Repite el paso 5. Dentro de `destino`, `systemctl` no arranca nada: el PID 1 es `sleep` |
| `UNPROTECTED PRIVATE KEY FILE` y `bad permissions` | `/tmp/ana-ssh` está en `644`. `chmod 644` la deja igual de abierta | `chmod 600 /tmp/ana-ssh` y repite el paso 8 |
| `account is locked` en el log de `sshd`, y la sesión es `Permission denied` | Falta `usermod -p "*"` | Repite el paso 5 |
| `Permission denied` en el paso 8, con la clave en `600` | Falta `/tmp/ana-ssh-cert.pub` al lado de la privada, o la CA no está en el servidor | Repite los pasos 5 y 7. El certificado tiene que llamarse `ana-ssh-cert.pub` |
| `http=403` al firmar | El token no es el de `ana`, o la policy no tiene `ssh/sign/acceso` | Repite los pasos 4 y 7 |
| `http=400` al crear el rol, con `expected a map` | `default_extensions` se envió como texto | Usa el `curl` del paso 3 |
