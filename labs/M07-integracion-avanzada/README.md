# M07 — Integración avanzada

[← Página anterior](../M06-testing-integraciones/03-lab-contrato-de-la-respuesta.md) · [Siguiente página →](00-secreto-sin-echo.md)

En el módulo 5 la aplicación dice la clave en voz alta para que veas que llegó. Esa misma frase es el fallo que un test de integración tiene que cazar: el valor queda en el log. Aquí la prueba demuestra que la integración funciona y la salida no lleva el secreto.

## Qué aprenderás

- Registrar la huella del fuente de negocio y dejar que Vault Agent inyecte la clave solo si ese fichero no ha cambiado.
- Entregar el `secret_id` dentro de un envoltorio de un solo uso, y ver que un echo de ese token no sirve para entrar.
- Firmar con el motor Transit a través del proxy de Agent, sin que la app reciba la clave privada ni el token.
- Entrar por SSH en un Ubuntu levantado con Docker: `ana` se autentica con UserPass y Vault le firma el certificado.
- Ejecutar las afirmaciones de fichero, envoltorio y firma Transit en una batería que escribe `PASS` o `FAIL`.

## Teoría

Hay cuatro entregas avanzadas. Las tres primeras usan Vault Agent en el contenedor `pagos`. La de SSH levanta un Ubuntu con `sshd`: Vault es la CA y un usuario UserPass obtiene el certificado con el que entra.

| Escenario | La salida enseña | El dato se queda |
|-----------|------------------|------------------|
| Huella del código | `codigo=certificado` y `pago=listo`; si el fuente cambia, `codigo=modificado` | La clave, en el entorno del proceso, solo cuando la huella coincide |
| Envoltorio | Un login `400` y un segundo unwrap `400` | El `secret_id`, abierto una vez por Agent |
| Firma Transit | `firma_prefijo=vault:v1:` y `valida=true` | La clave privada, dentro de Transit |
| SSH | `ana` y `acceso=ok` dentro del Ubuntu | La CA privada en Vault; sin certificado, `sshd` niega la sesión |

La huella es el prefijo de doce caracteres del sha256 de `negocio.sh`, guardada en Vault al certificar el fuente. Agent la lee y la vuelve a medir en la máquina de la aplicación. El proceso que arranca es `validar.sh`: si coinciden, hace `exec` de `negocio.sh` y ese proceso hereda `CLAVE`. Si alguien editó el fuente para imprimir la clave, `negocio.sh` no arranca.

```text
huella del código               envoltorio                      firma Transit                 SSH
vault agent                     vault agent                     vault agent                   motor ssh/ + sshd
  lee la huella registrada       unwrap del wrapping token       proxy 127.0.0.1:8100           CA en el Ubuntu
  mide negocio.sh                 el secret_id no se imprime      firmar.sh pide la firma       ana entra con UserPass
  solo entonces inyecta CLAVE     el token de entrega ya no vale  imprime vault:v1:             sesión por el puerto 2222
```

El envoltorio es response wrapping. `vault write -wrap-ttl` devuelve un wrapping token. Ese token no es un `secret_id`: el login con él responde `invalid role or secret ID`. Agent, con `secret_id_response_wrapping_path`, lo abre una vez. El segundo `vault unwrap` responde `wrapping token is not valid or does not exist`.

La firma Transit usa el motor `transit`. La app manda el texto `pago:42` al proxy local. Agent añade su token. Transit devuelve `vault:v1:…` y `transit/verify` dice `valid: true`. Leer `transit/export/signing-key/pagos` con el token `root` responde `private key material is not exportable`.

SSH no es el motor `pki` (X.509). Es `ssh/` con `key_type=ca` y una CA Ed25519. El Ubuntu confía en esa pública. `ana` entra con UserPass, Vault firma su clave para el principal `ana` y `ssh` abre la sesión. Sin el certificado, `sshd` responde `Permission denied`. Pedir el principal `root` responde 400.

> [!NOTE]
> El log de Agent, al arrancar el proxy, avisa de que esa función pasa al subcomando `vault proxy`. En este módulo el proceso sigue siendo `vault agent`.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [El secreto no sale por el echo](00-secreto-sin-echo.md) | Huella del código, envoltorio y firma Transit, en un mismo servidor |
| 01 | [La huella del código](01-lab-huella-del-codigo.md) | Agent entrega la clave si el fuente coincide, y se niega si alguien lo modifica |
| 02 | [secret_id envuelto](02-lab-secret-id-envuelto.md) | El token de entrega no entra, y Agent lo gasta |
| 03 | [La app firma](03-lab-firma-transit.md) | `vault:v1:` y la clave privada no se exporta |
| 04 | [Entrar por SSH](04-lab-ssh-ca.md) | UserPass, certificado y sesión en el Ubuntu |
| 05 | [La batería](05-lab-bateria.md) | Tres `PASS` (fichero, envoltorio, firma Transit) |

→ Empieza por **[00 — El secreto no sale por el echo](00-secreto-sin-echo.md)**.
