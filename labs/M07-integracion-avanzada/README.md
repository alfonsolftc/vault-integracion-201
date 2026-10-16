# M07 — Integración avanzada

[← Página anterior](../M06-testing-integraciones/03-lab-contrato-de-la-respuesta.md) · [Siguiente página →](00-secreto-sin-echo.md)

En el módulo 5 la aplicación dice la clave en voz alta para que veas que llegó. Esa misma frase es el fallo que un test de integración tiene que cazar: el valor queda en el log. Aquí la prueba demuestra que la integración funciona y la salida no lleva el secreto.

## Qué aprenderás

- Dejar el secreto en un fichero de modo `600` con Vault Agent, y afirmar una huella en vez del valor.
- Entregar el `secret_id` dentro de un envoltorio de un solo uso, y ver que un echo de ese token no sirve para entrar.
- Firmar con el motor Transit a través del proxy de Agent, sin que la app reciba la clave privada ni el token.
- Usar el motor SSH como CA: Vault firma la clave pública y el certificado lleva el principal; la CA privada no sale.
- Ejecutar las afirmaciones de fichero, envoltorio y firma Transit en una batería que escribe `PASS` o `FAIL`.

## Teoría

Hay cuatro entregas avanzadas. Las tres primeras usan Vault Agent en el contenedor `pagos`. La de SSH usa el motor `ssh` en modo CA: no reparte una contraseña, firma un certificado OpenSSH.

| Escenario | La salida enseña | El dato se queda |
|-----------|------------------|------------------|
| Fichero | `huella=` de 12 hexadecimales y `modo=600` | El valor, en `/tmp/clave` |
| Envoltorio | Un login `400` y un segundo unwrap `400` | El `secret_id`, abierto una vez por Agent |
| Firma Transit | `firma_prefijo=vault:v1:` y `valida=true` | La clave privada, dentro de Transit |
| SSH CA | Tipo `user certificate` y principal `pagos` | La CA privada en Vault; la del cliente, en modo 600 |

En Vault 1.18 un bloque `exec` exige al menos un `env_template`, y un `template` de fichero no puede ir en el mismo `agent.hcl` que un `env_template`. El `exec` del módulo 5 mete la clave en el entorno del proceso. Aquí Agent queda en marcha, escribe el fichero y el proceso de negocio se arranca aparte.

```text
fichero                         envoltorio                      firma Transit                 SSH CA
vault agent                     vault agent                     vault agent                   motor ssh/
  template → /tmp/clave 0600      unwrap del wrapping token       proxy 127.0.0.1:8100           config/ca + roles/
negocio.sh lee el fichero       el secret_id no se imprime      firmar.sh pide la firma       cliente: clave pública
imprime la huella               el token de entrega ya no vale   imprime vault:v1:             certificado *-cert.pub
```

El envoltorio es response wrapping. `vault write -wrap-ttl` devuelve un wrapping token. Ese token no es un `secret_id`: el login con él responde `invalid role or secret ID`. Agent, con `secret_id_response_wrapping_path`, lo abre una vez. El segundo `vault unwrap` responde `wrapping token is not valid or does not exist`.

La firma Transit usa el motor `transit`. La app manda el texto `pago:42` al proxy local. Agent añade su token. Transit devuelve `vault:v1:…` y `transit/verify` dice `valid: true`. Leer `transit/export/signing-key/pagos` con el token `root` responde `private key material is not exportable`.

SSH CA no es el motor `pki` (X.509). Es `ssh/` con `key_type=ca`. Vault firma la pública del cliente; `ssh-keygen -L` muestra el principal y la CA. Pedir un principal fuera de `allowed_users` responde 400.

> [!NOTE]
> El log de Agent, al arrancar el proxy, avisa de que esa función pasa al subcomando `vault proxy`. En este módulo el proceso sigue siendo `vault agent`.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [El secreto no sale por el echo](00-secreto-sin-echo.md) | Fichero, envoltorio y firma Transit, en un mismo servidor |
| 01 | [La huella en el fichero](01-lab-huella-en-fichero.md) | La huella cambia al rotar y el valor no aparece |
| 02 | [secret_id envuelto](02-lab-secret-id-envuelto.md) | El token de entrega no entra, y Agent lo gasta |
| 03 | [La app firma](03-lab-firma-transit.md) | `vault:v1:` y la clave privada no se exporta |
| 04 | [SSH con Vault como CA](04-lab-ssh-ca.md) | Certificado de usuario con principal `pagos` |
| 05 | [La batería](05-lab-bateria.md) | Tres `PASS` (fichero, envoltorio, firma Transit) |

→ Empieza por **[00 — El secreto no sale por el echo](00-secreto-sin-echo.md)**.
