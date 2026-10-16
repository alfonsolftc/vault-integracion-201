# Entrar por SSH

[← Página anterior](03-lab-firma-transit.md) · [Siguiente página →](05-lab-certificado-en-destino.md)

Vault administra quién entra en un servidor. El servidor es un Ubuntu que arrancas con Docker: tiene `sshd` y el usuario de sistema `ana`, y no tiene contraseña. `ana` entra en Vault con UserPass. `vault ssh -mode=ca` firma su clave y abre la sesión. Sin esa firma, `sshd` responde `Permission denied`. Pedir el principal `root` no produce certificado.

### Objetivo

`vault ssh -mode=ca -role=acceso` escribe `ana` y `acceso=ok`. La misma orden con `-valid-principals=root` termina en `salida=2` y `root is not a valid value for valid_principals`.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. El comando `vault` de esta terminal corre dentro de `vault-dev` cuando no hay CLI instalado en la máquina. El contenedor `destino` se crea en esta página. Quítalo al final: el comando está en el último paso.

### En qué consiste

Crear la CA en el motor `ssh`, levantar el Ubuntu y dejar que confíe en esa CA, y entrar con `vault ssh -mode=ca` usando el token de `ana`.

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
  --data '{"key_type":"ca","allow_user_certificates":true,"allowed_users":"ana","default_user":"ana","allowed_extensions":"permit-pty,permit-X11-forwarding,permit-agent-forwarding,permit-port-forwarding,permit-user-rc","default_extensions":{"permit-pty":""},"ttl":"30m","max_ttl":"30m"}' \
  "${VAULT_ADDR}/v1/ssh/roles/acceso"
```

**Por qué:** el rol `acceso` solo puede firmar el principal `ana`. `vault ssh` pide, además de `permit-pty`, las extensiones de reenvío. Si el rol no las admite, la firma responde 400 y no hay sesión. El certificado caduca a los treinta minutos. El cuerpo va en JSON porque `default_extensions` es un mapa: el CLI lo manda como texto y Vault responde 400.

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
docker run -d --name destino --network "$RED" ubuntu:24.04 sleep infinity
docker exec destino bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq openssh-server >/tmp/apt.log 2>&1 && echo sshd=instalado'
docker cp /tmp/vault-ssh-ca.pub destino:/etc/ssh/vault-ca.pub
docker exec destino bash -c 'useradd -m -s /bin/bash ana && usermod -p "*" ana && mkdir -p /run/sshd && printf "%s\n" "TrustedUserCAKeys /etc/ssh/vault-ca.pub" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "PubkeyAuthentication yes" "UsePAM no" > /etc/ssh/sshd_config.d/vault.conf && ssh-keygen -A && /usr/sbin/sshd && ssh-keygen -lf /etc/ssh/vault-ca.pub && pgrep -a sshd && echo cuenta=ana'
```

**Por qué:** `destino` es la máquina a la que se entra. Comparte la red de `vault-dev`, así que desde ese contenedor el nombre `destino` es el puerto `22`. El Ubuntu no trae `sshd` y, al instalarlo, no lo arranca: el PID 1 es `sleep` y no hay systemd. `useradd` deja la cuenta bloqueada y entonces ignora el certificado (`account is locked`); `usermod -p "*"` abre la cuenta sin crear una contraseña. `TrustedUserCAKeys` apunta a la pública del paso 2.

**Resultado esperado:** `red=infra_default`, `sshd=instalado`, una línea `256 SHA256:… (ED25519)` con la misma huella del paso 2, una línea con `/usr/sbin/sshd` y `listener`, y `cuenta=ana`. La primera vez Docker descarga `ubuntu:24.04`.

### 6 — El cliente ssh, en el mismo sitio que el CLI

**Acción:**

```bash
docker exec -u root vault-dev sh -c 'apk add --no-cache openssh-client >/tmp/apk.log 2>&1 && command -v ssh'
docker exec vault-dev sh -c 'rm -f /tmp/ana-ssh /tmp/ana-ssh.pub; ssh-keygen -t ed25519 -N "" -f /tmp/ana-ssh -C ana@lab -q; stat -c "modo=%a" /tmp/ana-ssh'
```

**Por qué:** `vault ssh` no abre la sesión él solo: llama al programa `ssh` en la máquina donde corre el CLI. En este curso esa máquina es el contenedor `vault-dev`, y la imagen no trae `ssh`. La clave de `ana` nace ahí, modo `600`. Vault solo va a ver la pública. El destino del paso siguiente es `ana@destino`, no `127.0.0.1`.

**Resultado esperado:** `/usr/bin/ssh` y `modo=600`.

### 7 — Entra con vault ssh

**Acción:**

```bash
curl -sS -o /tmp/ana.json -w "http=%{http_code}\n" --request POST \
  --data '{"password":"ana-lab"}' \
  "${VAULT_ADDR}/v1/auth/userpass/login/ana"
ANA=$(python3 -c 'import json; print(json.load(open("/tmp/ana.json"))["auth"]["client_token"])')
echo "token_len=${#ANA}"
VAULT_TOKEN="$ANA" vault ssh -mode=ca -role=acceso \
  -public-key-path=/tmp/ana-ssh.pub \
  -private-key-path=/tmp/ana-ssh \
  -strict-host-key-checking=no \
  -user-known-hosts-file=/dev/null \
  -valid-principals=ana \
  ana@destino \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o LogLevel=ERROR \
  'whoami; echo acceso=ok'
```

**Por qué:** el login es el de `ana` / `ana-lab`. `VAULT_TOKEN` de esta orden es el suyo, no el `root`: la policy `firma-ssh` es la que firma. `-mode=ca` pide el certificado al rol `acceso` y conecta a `destino`. La privada no sale de `vault-dev`. No hay contraseña en el servidor.

**Resultado esperado:** el login es `http=200` y `token_len=95`. Después:

```text
ana
acceso=ok
```

![vault ssh -mode=ca entra como ana y el servidor escribe acceso=ok](../img/M07-04-cert.png)

### 8 — Un principal que el rol no firma

**Acción:**

```bash
VAULT_TOKEN="$ANA" vault ssh -mode=ca -role=acceso \
  -public-key-path=/tmp/ana-ssh.pub \
  -private-key-path=/tmp/ana-ssh \
  -valid-principals=root \
  ana@destino 'whoami' || echo "salida=$?"
```

**Por qué:** el rol solo admite `ana`. `-valid-principals=root` no abre una sesión de administrador: Vault responde 400 y `vault ssh` no llega a conectar.

**Resultado esperado:** `Code: 400`, la línea `root is not a valid value for valid_principals` y `salida=2`.

![Pedir el principal root responde 400](../img/M07-04-root.png)

### 9 — Quita el servidor

**Acción:**

```bash
docker rm -f destino >/dev/null
```

**Por qué:** para `sshd`. El servidor `vault-dev` sigue. El paquete `openssh-client` que quedó en `vault-dev` desaparece al reiniciar Vault.

**Resultado esperado:** termina sin texto.

> [!WARNING]
> Si pasas a otra página sin este paso, `bash infra/reiniciar-vault.sh` también elimina `destino`.

## Comprueba tu entendimiento

**La privada de ana no viajó a Vault**

```bash
docker exec vault-dev sh -c 'grep -c "BEGIN OPENSSH PRIVATE KEY" /tmp/ana-ssh; stat -c "modo=%a" /tmp/ana-ssh'
```

→ `1` y `modo=600`. Esa clave sigue dentro de `vault-dev`. Vault solo recibió la pública para firmarla.

## Reto

### 1 — La clave sola no entra

Con `destino` todavía en marcha, entra en `ana@destino` usando `/tmp/ana-ssh` y sin `vault ssh`.

<details>
<summary>Ver solución</summary>

```bash
docker exec vault-dev ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -o ConnectTimeout=5 \
  ana@destino whoami || echo "salida=$?"
```

`Permission denied (publickey).` y `salida=255`. No hay `authorized_keys`. `sshd` solo fía de un certificado firmado por la CA. Al acabar: `docker rm -f destino`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `ssh-keygen: command not found` en el paso 2 | Falta `openssh-client` en esta terminal | El `apt-get` del paso 2 |
| `failed to sign` y `extensions [permit-X11-forwarding …] are not on allowed list` | El rol no admite las extensiones que pide `vault ssh` | Repite el `curl` del paso 3 |
| `pgrep` no imprime nada | El paquete se instaló y `/usr/sbin/sshd` no llegó a lanzarse | Repite el paso 5. Dentro de `destino`, `systemctl` no arranca nada: el PID 1 es `sleep` |
| `account is locked` en el log de `sshd`, y la sesión es `Permission denied` | Falta `usermod -p "*"` | Repite el paso 5 |
| `ssh: executable file not found` o `exec: "ssh": executable file not found` | El cliente `ssh` no está en `vault-dev` | Repite el paso 6 |
| `failed to read public key /tmp/ana-ssh.pub` | La clave se generó en esta terminal y el CLI corre dentro de `vault-dev` | La clave tiene que nacer con el `docker exec vault-dev ssh-keygen` del paso 6 |
| `Permission denied` en el paso 7 | La CA no está en `/etc/ssh/vault-ca.pub`, o `sshd` arrancó antes de copiarla | Repite el paso 5 y el paso 7 |
| `http=403` al firmar | El token no es el de `ana`, o la policy no tiene `ssh/sign/acceso` | Repite los pasos 4 y 7. `VAULT_TOKEN="$ANA"` tiene que ir delante de `vault ssh` |
| `http=400` al crear el rol, con `expected a map` | `default_extensions` se envió como texto | Usa el `curl` del paso 3 |
| `Could not resolve hostname destino` | `destino` no está en la red de `vault-dev`, o el CLI de Vault está instalado en esta máquina y no dentro del contenedor | `echo "$RED"` tiene que ser la red de `vault-dev`. Repite el paso 5 |
