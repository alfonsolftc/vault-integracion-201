# Entrar por SSH

[← Página anterior](03-lab-firma-transit.md) · [Siguiente página →](05-lab-bateria.md)

Vault administra quién entra en un servidor. El servidor es un Ubuntu que arrancas con Docker: tiene `sshd` y el usuario de sistema `ana`, y no tiene contraseña. Vault Agent corre dentro de esa Ubuntu. Escribe la pública de la CA y, cuando `ana` firma, escribe su certificado en `/home/ana/.ssh/ana-ssh-cert.pub`. Nadie lo copia a mano. `ana` entra en Vault con UserPass, presenta ese certificado y abre la sesión SSH. Sin él, `sshd` responde `Permission denied`.

### Objetivo

Una sesión SSH que escribe `ana` y `acceso=ok`. Sin el fichero del certificado, la misma orden termina en `salida=255` y `Permission denied (publickey).` Pedir el principal `root` responde `http=400`.

### Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. Hace falta `ssh-keygen` y el cliente `ssh` en esta terminal (paquete `openssh-client`). Si no están:

```bash
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client
```

El contenedor `destino` se crea en esta página. Quítalo al final: el comando está en el último paso.

### En qué consiste

Crear la CA en el motor `ssh`, levantar el Ubuntu, dejar que Agent escriba ahí la CA y el certificado de `ana`, entrar con UserPass y usar ese certificado para abrir la sesión SSH.

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

**Por qué:** ese fichero es el que el servidor pondrá en `TrustedUserCAKeys`. La lista de campos confirma que la lectura no trae la privada.

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

**Por qué:** el rol `acceso` solo puede firmar el principal `ana`, que es el usuario de sistema del servidor. `permit-pty` permite abrir un terminal. El certificado caduca a los treinta minutos. El cuerpo va en JSON porque `default_extensions` es un mapa: el CLI lo manda como texto y Vault responde 400.

**Resultado esperado:** `http=204`. Un 204 es el alta, sin cuerpo.

### 4 — Policy y UserPass de ana

**Acción:**

```bash
bash infra/policy.sh firma-ssh <<'EOF'
path "ssh/sign/acceso" {
  capabilities = ["create", "update"]
}
path "secret/data/ssh/ana" {
  capabilities = ["create", "update"]
}
EOF
vault auth enable userpass
vault write auth/userpass/users/ana password=ana-lab policies=firma-ssh
```

**Por qué:** `ana` es una persona. Entra con usuario y contraseña, como en el módulo 4, y el token solo puede firmar en `ssh/sign/acceso` y guardar ese certificado en `secret/ssh/ana`. No exporta la CA. El token `root` sigue en esta terminal para los pasos de administración.

**Resultado esperado:** `Policy firma-ssh escrita.`, `Success! Enabled userpass auth method at: userpass/` y `Success! Data written to: auth/userpass/users/ana`.

### 5 — Levanta el servidor

**Acción:**

```bash
docker rm -f destino >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
docker run -d --name destino -p 127.0.0.1:2222:22 --network "$RED" ubuntu:24.04 sleep infinity
```

**Por qué:** `destino` es la máquina a la que Vault va a dar acceso. La imagen es Ubuntu 24.04, todavía sin SSH: `sleep infinity` solo la mantiene encendida. El puerto `2222` de esta máquina es el `22` del contenedor. La red es la de `vault-dev` por si desde esta terminal no llegas a `127.0.0.1:2222`.

**Resultado esperado:** `red=infra_default` y un identificador de contenedor. La primera vez Docker descarga `ubuntu:24.04`.

### 6 — Instala el servidor SSH

**Acción:**

```bash
docker exec destino bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq openssh-server >/tmp/apt.log 2>&1 && mkdir -p /run/sshd && ssh-keygen -A && /usr/sbin/sshd && pgrep -a sshd'
```

**Por qué:** el Ubuntu de Docker no trae `sshd`, y al instalarlo no lo arranca: el PID 1 es `sleep` y no hay systemd. `systemctl` no tiene bus. Este paso instala el paquete y lanza `/usr/sbin/sshd`. La salida de `apt` se queda en el contenedor. Dentro de `destino`, la comprobación es `pgrep -a sshd`; el puerto de ese proceso es el `22`.

**Resultado esperado:** una línea con `/usr/sbin/sshd` y `listener`. Tarda un poco: está instalando el paquete.

### 7 — Prepara la cuenta y apunta sshd a la CA

**Acción:**

```bash
docker exec destino bash -c 'id ana >/dev/null 2>&1 || useradd -m -s /bin/bash ana; usermod -p "*" ana; mkdir -p /home/ana/.ssh /run/sshd; printf "%s\n" "TrustedUserCAKeys /etc/ssh/vault-ca.pub" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "PubkeyAuthentication yes" "UsePAM no" > /etc/ssh/sshd_config.d/vault.conf; echo cuenta=ana'
```

**Por qué:** `TrustedUserCAKeys` nombra el fichero donde Agent va a escribir la pública de Vault. Ese fichero todavía no existe: `sshd` sigue con la configuración del paso 6 hasta que Agent lo reinicie. `useradd` deja la cuenta bloqueada y entonces ignora el certificado (`account is locked`); `usermod -p "*"` abre la cuenta sin crear una contraseña. `PasswordAuthentication no` cierra el otro camino.

**Resultado esperado:** `cuenta=ana`.

### 8 — Agent escribe la CA en la Ubuntu

**Acción:**

```bash
bash infra/policy.sh entrega-ssh <<'EOF'
path "ssh/config/ca" {
  capabilities = ["read"]
}
path "secret/data/ssh/ana" {
  capabilities = ["read"]
}
path "secret/metadata/ssh/ana" {
  capabilities = ["read"]
}
EOF
vault auth enable approle
vault write auth/approle/role/destino \
  token_policies=entrega-ssh \
  token_ttl=15m \
  token_max_ttl=1h
ROLE_ID=$(vault read -field=role_id auth/approle/role/destino/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/destino/secret-id)
cid=$(docker create hashicorp/vault:1.18)
docker cp "$cid":/bin/vault /tmp/vault-bin
docker rm "$cid" >/dev/null
docker cp /tmp/vault-bin destino:/usr/local/bin/vault
docker exec destino chmod +x /usr/local/bin/vault
printf '%s' "$ROLE_ID" | docker exec -i destino tee /tmp/role_id >/dev/null
printf '%s' "$SECRET_ID" | docker exec -i destino tee /tmp/secret_id >/dev/null
docker exec -i destino tee /tmp/agent.hcl >/dev/null <<'EOF'
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
  destination = "/etc/ssh/vault-ca.pub"
  perms = "0644"
  contents = "{{ with secret \"ssh/config/ca\" }}{{ .Data.public_key }}{{ end }}\n"
  command = "/bin/sh -c 'pkill sshd || true; sleep 0.3; mkdir -p /run/sshd; /usr/sbin/sshd'"
}

template {
  destination = "/home/ana/.ssh/ana-ssh-cert.pub"
  create_dest_dirs = true
  perms = "0644"
  contents = "{{ with secret \"secret/data/ssh/ana\" }}{{ .Data.data.certificado }}{{ end }}\n"
}
EOF
docker exec -d destino sh -c '/usr/local/bin/vault agent -config=/tmp/agent.hcl > /tmp/agent.log 2>&1'
for i in $(seq 1 30); do
  docker exec destino test -s /etc/ssh/vault-ca.pub && break
  sleep 0.3
done
docker exec destino ssh-keygen -lf /etc/ssh/vault-ca.pub
docker exec destino pgrep -a sshd
```

**Por qué:** la Ubuntu no trae el binario `vault`; se copia de la imagen `hashicorp/vault:1.18` para ejecutar Agent. Agent entra con AppRole, lee `ssh/config/ca` y escribe `/etc/ssh/vault-ca.pub`. Al terminar, reinicia `sshd`, que a partir de ahí confía en esa CA. El certificado de `ana` todavía no existe: en el log puede salir `no secret exists at secret/data/ssh/ana`. Es la espera del otro template.

**Resultado esperado:** `Policy entrega-ssh escrita.`, el alta de AppRole, una línea `256 SHA256:… (ED25519)` y otra con `/usr/sbin/sshd` y `listener`. La huella es la misma del paso 2.

### 9 — Elige por dónde llegar al servidor

**Acción:**

```bash
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' destino | awk '{print $1}')
if timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/2222' 2>/dev/null; then
  SSH_HOST=127.0.0.1
  SSH_PORT=2222
else
  SSH_HOST=$IP
  SSH_PORT=22
fi
export SSH_HOST SSH_PORT
echo "ssh_host=${SSH_HOST} ssh_port=${SSH_PORT}"
```

**Por qué:** en Docker local el puerto publicado es `127.0.0.1:2222`. En un Codespace que no ve ese puerto, la sesión va a la IP de `destino` en la red de Vault, puerto `22`. Las órdenes siguientes usan estas dos variables.

**Resultado esperado:** `ssh_host=127.0.0.1 ssh_port=2222`, o `ssh_host=` con una IP y `ssh_port=22`.

### 10 — Genera el par de ana

**Acción:**

```bash
rm -f /tmp/ana-ssh /tmp/ana-ssh.pub /tmp/ana-ssh-cert.pub
ssh-keygen -t ed25519 -N '' -f /tmp/ana-ssh -C 'ana@lab' -q
stat -c 'modo=%a' /tmp/ana-ssh
```

**Por qué:** la clave privada nace en esta máquina, con modo `600`. Vault solo va a ver la pública. El certificado tendrá que llamarse `/tmp/ana-ssh-cert.pub`: OpenSSH lo busca al lado de `/tmp/ana-ssh`.

**Resultado esperado:** `modo=600`.

### 11 — Entra con UserPass y firma la pública

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
python3 -c 'import json; d=json.load(open("/tmp/ssh-sign.json")); open("/tmp/ana-ssh-cert.pub","w").write(d["data"]["signed_key"]); print("cert_bytes", len(d["data"]["signed_key"]))'
export CERT="$(cat /tmp/ana-ssh-cert.pub)"
curl -sS -o /dev/null -w "guardado=%{http_code}\n" \
  --header "X-Vault-Token: ${ANA}" \
  --request POST \
  --data "$(python3 -c 'import json,os; print(json.dumps({"data":{"certificado": os.environ["CERT"]}}))')" \
  "${VAULT_ADDR}/v1/secret/data/ssh/ana"
```

**Por qué:** el login es el de `ana` / `ana-lab`. El token que firma es el suyo, no el `root`. Vault recibe la pública y el principal `ana`, y devuelve un certificado. La privada no sale de esta máquina. El mismo token guarda el certificado en `secret/ssh/ana`: es el dato que Agent está esperando.

**Resultado esperado:** el login es `http=200` y `token_len=95`. La firma es `http=200` y `cert_bytes` por encima de 500. La última línea es `guardado=200`.

### 12 — El certificado aparece en la Ubuntu

**Acción:**

```bash
for i in $(seq 1 20); do
  docker exec destino test -s /home/ana/.ssh/ana-ssh-cert.pub && break
  sleep 1
done
echo "esperas=$i"
docker exec destino ssh-keygen -L -f /home/ana/.ssh/ana-ssh-cert.pub
```

**Por qué:** Agent relee `secret/ssh/ana` cada cinco segundos y escribe `/home/ana/.ssh/ana-ssh-cert.pub`. No hay `docker cp`. `sshd` no autoriza leyendo ese fichero: autoriza porque el certificado que presenta el cliente está firmado por la CA de `/etc/ssh/vault-ca.pub`. El fichero es la prueba de que el certificado de `ana` está en la Ubuntu.

**Resultado esperado:** `esperas=` es un entero pequeño. En la salida de `ssh-keygen` aparecen:

- `Type: ssh-ed25519-cert-v01@openssh.com user certificate`
- `Principals:` y debajo `ana`
- `permit-pty`
- `Valid: from … to …` con un margen de treinta minutos

### 13 — Entra en el servidor

**Acción:**

```bash
ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -p "$SSH_PORT" \
  "ana@${SSH_HOST}" \
  'whoami; echo acceso=ok'
```

**Por qué:** esta es la prueba de integración. `sshd` acepta el certificado porque está firmado por la CA que tiene en `TrustedUserCAKeys` y el principal es el usuario `ana`. No hay contraseña en el servidor.

**Resultado esperado:**

```text
ana
acceso=ok
```

![ana entra por SSH y el servidor escribe acceso=ok](../img/M07-04-cert.png)

### 14 — Sin el certificado no hay sesión

**Acción:**

```bash
mv /tmp/ana-ssh-cert.pub /tmp/ana-ssh-cert.bak
ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=5 \
  -p "$SSH_PORT" \
  "ana@${SSH_HOST}" 'whoami' || echo "salida=$?"
mv /tmp/ana-ssh-cert.bak /tmp/ana-ssh-cert.pub
```

**Por qué:** la clave privada sola no está en `authorized_keys`. El servidor solo fía de la CA de Vault. Al apartar el certificado, la misma clave deja de entrar. El `mv` final lo devuelve a su sitio.

**Resultado esperado:** una línea `Permission denied (publickey).` y `salida=255`.

### 15 — Un principal que el rol no firma

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

**Por qué:** el rol solo admite `ana`. Pedir `root` no produce un certificado de administrador: Vault responde 400.

**Resultado esperado:** `http=400` y `['root is not a valid value for valid_principals']`.

![Pedir el principal root responde 400](../img/M07-04-root.png)

### 16 — Quita el servidor

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
`grep -c PRIVATE /tmp/ana-ssh-cert.pub; stat -c 'modo=%a' /tmp/ana-ssh`
→ El certificado imprime `0`. La clave privada sigue en `/tmp/ana-ssh`, modo `600`.

## Reto

### 1 — El certificado de ana no sirve para root

Con `destino` todavía en marcha y el certificado en su sitio, intenta entrar como `root` usando `/tmp/ana-ssh`.

<details>
<summary>Ver solución</summary>

```bash
ssh -i /tmp/ana-ssh \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=5 \
  -p "$SSH_PORT" \
  "root@${SSH_HOST}" 'whoami' || echo "salida=$?"
```

`Permission denied (publickey).` y `salida=255`. El certificado dice principal `ana`. `sshd` no lo acepta para `root`. Al acabar: `docker rm -f destino`.

</details>

## Errores frecuentes

| Síntoma | Causa probable | Cómo arreglarlo |
|---------|----------------|-----------------|
| `ssh-keygen: command not found` o `ssh: command not found` | Falta `openssh-client` | El `apt-get` del punto de partida |
| `pgrep` no imprime nada tras el paso 6 | El paquete se instaló y `/usr/sbin/sshd` no llegó a lanzarse | Repite el paso 6. Dentro de `destino`, `systemctl` no arranca nada: el PID 1 es `sleep` |
| `account is locked` en el log de `sshd`, y la sesión es `Permission denied` | Falta `usermod -p "*"` | Repite el paso 7 |
| `esperas=20` y el fichero no está | Agent no relee el KV, o `guardado=` no fue 200 | `docker exec destino tail /tmp/agent.log`. Tiene que existir `static_secret_render_interval` y el POST de `secret/data/ssh/ana` |
| `Permission denied` en el paso 13 | El certificado no está en `/tmp/ana-ssh-cert.pub`, o `SSH_HOST` apunta a otro sitio | Repite los pasos 9, 11 y 13. `echo "$SSH_HOST $SSH_PORT"` tiene que coincidir con un `destino` vivo |
| `http=403` al firmar o al guardar | El token no es el de `ana`, o la policy no tiene `ssh/sign/acceso` ni `secret/data/ssh/ana` | Repite los pasos 4 y 11 |
| `http=400` al crear el rol, con `expected a map` | `default_extensions` se envió como texto | Usa el `curl` del paso 3 |
| `bind: address already in use` en el puerto 2222 | Quedó un `destino` de un intento anterior | `docker rm -f destino` y repite el paso 5 |
| `root is not a valid value` en el paso 11 | El JSON pide `root` | El 400 de `root` es el resultado bueno del paso 15 |
