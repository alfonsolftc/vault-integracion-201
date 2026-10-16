# El secreto no sale por el echo

[← Página anterior](README.md) · [Siguiente página →](01-lab-huella-del-codigo.md)

La aplicación de pagos sigue necesitando la clave. La prueba ya no consiste en oírla. Vault Agent mide el fuente de negocio y solo inyecta la clave si esa huella es la que se certificó. El `secret_id` llega envuelto y, cuando la app solo tiene que firmar, la clave privada no sale de Transit.

## Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

`vault-dev` queda vacío. La terminal tiene `VAULT_ADDR=http://127.0.0.1:8200` y el token `root` de laboratorio. Ese token no entra en la aplicación.

## Recorrido

1. El secreto, la policy de solo lectura y el rol AppRole `pagos` existen antes de la aplicación. `ROLE_ID` y `SECRET_ID` se quedan en esta terminal. La clave no se imprime.

```bash
vault kv put secret/pagos/api clave=clave-v1
bash infra/policy.sh solo-pagos <<'EOF'
path "secret/data/pagos/api" {
  capabilities = ["read"]
}
path "secret/data/pagos/codigo" {
  capabilities = ["read"]
}
EOF
vault auth enable approle
vault write auth/approle/role/pagos token_policies=solo-pagos token_ttl=15m token_max_ttl=1h
ROLE_ID=$(vault read -field=role_id auth/approle/role/pagos/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/pagos/secret-id)
export ROLE_ID SECRET_ID
echo "role_len=${#ROLE_ID} secret_len=${#SECRET_ID}"
```

La metadata queda en `version` `1`. La última línea es `role_len=36 secret_len=36`.

2. El contenedor `pagos` es la máquina de la aplicación, en la red de `vault-dev`. La imagen trae el binario `vault` para ejecutar Agent. El proceso de negocio es un `sh` que no llama a ese binario: recibe `CLAVE` solo después de que Agent haya comprobado la huella del fuente.

```bash
docker rm -f pagos >/dev/null 2>&1 || true
RED=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' vault-dev | head -n 1)
echo "red=$RED"
docker run -d --name pagos --network "$RED" --entrypoint sleep hashicorp/vault:1.18 86400
```

`red=` muestra el nombre de la red, en este laboratorio `infra_default`. Desde `pagos`, Vault se alcanza por `vault-dev`.

3. `/tmp/negocio.sh` es el fuente que se certifica. Exige `CLAVE` y escribe `pago=listo`. No escribe el valor. La huella de doce caracteres se calcula sobre ese fichero y se guarda en `secret/pagos/codigo`.

```bash
printf '%s' "$ROLE_ID" | docker exec -i pagos tee /tmp/role_id >/dev/null
printf '%s' "$SECRET_ID" | docker exec -i pagos tee /tmp/secret_id >/dev/null
docker exec -i pagos tee /tmp/negocio.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu
if [ -z "${CLAVE:-}" ]; then
  echo "falta CLAVE" >&2
  exit 1
fi
echo "pago=listo"
EOF
docker exec pagos chmod +x /tmp/negocio.sh
HUELLA=$(docker exec pagos sha256sum /tmp/negocio.sh | awk '{print substr($1,1,12)}')
vault kv put secret/pagos/codigo huella="$HUELLA" >/dev/null
echo "huella=${HUELLA}"
```

Los `tee` terminan sin texto. La última línea es `huella=b1501cb434fd`.

4. `validar.sh` es el proceso que arranca Agent. Mide `negocio.sh` y lo compara con `HUELLA`. Si coinciden, hace `exec` del proceso de negocio, que hereda `CLAVE`. `agent.hcl` entrega las dos variables y no arranca `negocio.sh` directamente.

```bash
docker exec -i pagos tee /tmp/validar.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu
medida=$(sha256sum /tmp/negocio.sh | awk '{print substr($1,1,12)}')
if [ "$medida" != "${HUELLA:-}" ]; then
  echo "codigo=modificado" >&2
  exit 1
fi
echo "codigo=certificado"
exec /bin/sh /tmp/negocio.sh
EOF
docker exec pagos chmod +x /tmp/validar.sh
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

env_template "CLAVE" {
  contents = "{{ with secret \"secret/data/pagos/api\" }}{{ .Data.data.clave }}{{ end }}"
}

env_template "HUELLA" {
  contents = "{{ with secret \"secret/data/pagos/codigo\" }}{{ .Data.data.huella }}{{ end }}"
}

exec {
  command = ["/bin/sh", "/tmp/validar.sh"]
  restart_on_secret_changes = "never"
}
EOF
docker exec pagos sh -c 'rm -f /tmp/vault-agent.pid; vault agent -config=/tmp/agent.hcl > /tmp/agent-ok.log 2>&1'
docker exec pagos grep -E 'codigo=certificado|pago=listo' /tmp/agent-ok.log
```

El primer comando termina en 0. Después salen `codigo=certificado` y `pago=listo`. El log también tiene `rendered "(dynamic)" => "CLAVE"`, sin el valor.

![Agent entrega la clave y el proceso escribe pago=listo](../img/M07-00-fichero.png)

5. Añadir `echo "$CLAVE"` cambia el fuente. La huella registrada sigue en `b1501cb434fd`. Agent vuelve a medir, no arranca `negocio.sh` y sale con código 1. Ni ese log ni el anterior contienen `clave-v1`.

```bash
docker exec pagos sh -c 'printf "%s\n" "echo \"\$CLAVE\"" >> /tmp/negocio.sh'
echo "registrada=$(vault kv get -field=huella secret/pagos/codigo)"
docker exec pagos sha256sum /tmp/negocio.sh | awk '{print "medida=" substr($1,1,12)}'
docker exec pagos sh -c 'rm -f /tmp/vault-agent.pid; vault agent -config=/tmp/agent.hcl > /tmp/agent-malo.log 2>&1' || echo "salida=$?"
docker exec pagos grep -E 'codigo=|pago=' /tmp/agent-malo.log
if docker exec pagos grep -q 'clave-v1' /tmp/agent-ok.log /tmp/agent-malo.log; then
  echo eco=si
else
  echo eco=no
fi
docker exec pagos rm -f /tmp/vault-agent.pid
```

`registrada=b1501cb434fd` y `medida=aa264905fb45`. Después, `salida=1`, `codigo=modificado` y `eco=no`. No aparece `pago=listo`: el proceso de negocio no ha arrancado.

6. El `secret_id` de la entrega siguiente no se escribe en claro. `-wrap-ttl=3m` devuelve un wrapping token. Esta terminal solo imprime su longitud. Usarlo como `secret_id` en el login responde 400, y el token sigue entero: ese POST no lo abre.

```bash
WRAP=$(vault write -wrap-ttl=3m -field=wrapping_token -f auth/approle/role/pagos/secret-id)
echo "wrap_len=${#WRAP}"
curl -sS -o /tmp/wrap-login.json -w "http=%{http_code}\n" --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${WRAP}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login"
python3 -c 'import json; print(json.load(open("/tmp/wrap-login.json")).get("errors"))'
```

`wrap_len=95`. Después, `http=400` y `['invalid role or secret ID']`.

7. Agent espera ese token en el fichero del `secret_id` y lo abre porque `secret_id_response_wrapping_path` nombra el camino donde se creó. Al leerlo, borra el fichero. La plantilla escribe `ok` en `/tmp/entrada`: hace falta un `template` para que el auto-auth arranque, y ese fichero no es la clave.

```bash
printf '%s' "$WRAP" | docker exec -i pagos tee /tmp/secret_id >/dev/null
docker exec -i pagos tee /tmp/wrap.hcl >/dev/null <<'EOF'
pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://vault-dev:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path = "/tmp/role_id"
      secret_id_file_path = "/tmp/secret_id"
      remove_secret_id_file_after_reading = true
      secret_id_response_wrapping_path = "auth/approle/role/pagos/secret-id"
    }
  }
}

template {
  destination = "/tmp/entrada"
  contents = "ok"
}
EOF
docker exec -d pagos sh -c 'vault agent -config=/tmp/wrap.hcl > /tmp/wrap.log 2>&1'
for i in $(seq 1 30); do
  docker exec pagos grep -q 'authentication successful' /tmp/wrap.log && break
  sleep 0.2
done
docker exec pagos grep -F 'authentication successful' /tmp/wrap.log
docker exec pagos cat /tmp/entrada
docker exec pagos sh -c 'if [ -f /tmp/secret_id ]; then echo fichero=sigue; else echo fichero=borrado; fi'
vault unwrap "$WRAP" || true
```

El log contiene `authentication successful`. `/tmp/entrada` es `ok`. La línea del fichero es `fichero=borrado`. El unwrap de esta terminal termina en código 2, con `Code: 400` y `wrapping token is not valid or does not exist`. El `secret_id` no llega a imprimirse: el único unwrap que funcionó lo hizo Agent, dentro del proceso.

![El login con el wrapping token es 400 y, tras Agent, el segundo unwrap ya no existe](../img/M07-00-envoltorio.png)

```bash
docker exec pagos sh -c 'kill $(cat /tmp/vault-agent.pid)'
```

8. La tercera entrega no reparte una clave. Transit crea `pagos` como clave Ed25519. `exportable` queda en `false`. La policy `firma-pagos` solo puede firmar y verificar. El rol `firma` no lee `secret/pagos/api`.

```bash
vault secrets enable transit
vault write -f transit/keys/pagos type=ed25519
bash infra/policy.sh firma-pagos <<'EOF'
path "transit/sign/pagos" {
  capabilities = ["update"]
}
path "transit/verify/pagos" {
  capabilities = ["update"]
}
EOF
vault write auth/approle/role/firma token_policies=firma-pagos token_ttl=15m token_max_ttl=1h
FROLE=$(vault read -field=role_id auth/approle/role/firma/role-id)
FSECRET=$(vault write -f -field=secret_id auth/approle/role/firma/secret-id)
echo "frole_len=${#FROLE} fsecret_len=${#FSECRET}"
```

En la respuesta de la clave aparecen `exportable false`, `supports_signing true` y `type ed25519`. También aparece `public_key`: es la mitad pública. La última línea es `frole_len=36 fsecret_len=36`.

9. Agent escucha en `127.0.0.1:8100` dentro de `pagos` y, con `use_auto_auth_token = true`, añade su token a las peticiones que llegan sin uno. `/tmp/firmar.sh` manda `pago:42`, comprueba la firma y pregunta el export. No escribe el token ni el cuerpo completo de la firma.

```bash
printf '%s' "$FROLE" | docker exec -i pagos tee /tmp/frole >/dev/null
printf '%s' "$FSECRET" | docker exec -i pagos tee /tmp/fsecret >/dev/null
docker exec -i pagos tee /tmp/firmar.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu
IN=$(printf %s 'pago:42' | base64 | tr -d '\n')
resp=$(wget -qO- --header='Content-Type: application/json' \
  --post-data="{\"input\":\"$IN\"}" \
  http://127.0.0.1:8100/v1/transit/sign/pagos)
firma=$(printf %s "$resp" | sed -n 's/.*"signature":"\([^"]*\)".*/\1/p')
case "$firma" in
  vault:v1:*) ;;
  *) echo "firma inesperada" >&2; exit 1 ;;
esac
ver=$(wget -qO- --header='Content-Type: application/json' \
  --post-data="{\"input\":\"$IN\",\"signature\":\"$firma\"}" \
  http://127.0.0.1:8100/v1/transit/verify/pagos)
printf %s "$ver" | grep -q '"valid":true'
codigo=$(wget -S -O /dev/null "http://127.0.0.1:8100/v1/transit/export/signing-key/pagos" 2>&1 | awk '/HTTP\// {print $2; exit}')
if printf %s "$resp$ver" | grep -q 'hvs\.'; then
  echo "token en salida" >&2
  exit 1
fi
echo "firma_prefijo=$(printf %s "$firma" | cut -c1-9) valida=true export_app=${codigo} token_en_salida=no"
EOF
docker exec pagos chmod +x /tmp/firmar.sh
docker exec -i pagos tee /tmp/proxy.hcl >/dev/null <<'EOF'
pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://vault-dev:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path = "/tmp/frole"
      secret_id_file_path = "/tmp/fsecret"
      remove_secret_id_file_after_reading = false
    }
  }
}

listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

api_proxy {
  use_auto_auth_token = true
}
EOF
docker exec -d pagos sh -c 'vault agent -config=/tmp/proxy.hcl > /tmp/proxy.log 2>&1'
for i in $(seq 1 30); do
  docker exec pagos grep -q 'authentication successful' /tmp/proxy.log && break
  sleep 0.2
done
docker exec pagos /bin/sh /tmp/firmar.sh
vault read transit/export/signing-key/pagos || true
docker rm -f pagos >/dev/null
```

La línea de la app es `firma_prefijo=vault:v1: valida=true export_app=403 token_en_salida=no`. El `vault read` del token `root` termina en código 2, con `Code: 400` y `private key material is not exportable`. El contenedor `pagos` desaparece. El log de Agent, si se abre entero, empieza avisando de que el proxy pasa a `vault proxy`; la firma de esta página sale igual.

![La app imprime el prefijo de la firma y el export de la clave privada responde 400](../img/M07-00-firma.png)

## Qué queda visto

Tres pruebas, y en ninguna sale el secreto. Agent entrega la clave solo si la huella del fuente coincide; si el script se modifica para imprimirla, el proceso no arranca. El wrapping token no entra en el login y, después de Agent, ya no se puede abrir. Transit firma `pago:42` y se niega a exportar la clave privada. Cada una se construye sola en [la huella del código](01-lab-huella-del-codigo.md), [secret_id envuelto](02-lab-secret-id-envuelto.md) y [la app firma](03-lab-firma-transit.md). Entrar por SSH en un Ubuntu, con un usuario UserPass y un certificado firmado por Vault, está en [Entrar por SSH](04-lab-ssh-ca.md). Las tres primeras juntas están en [la batería](05-lab-bateria.md).
