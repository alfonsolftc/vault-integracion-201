# M07 — Integración avanzada

[← Página anterior](../M06-testing-integraciones/03-lab-contrato-de-la-respuesta.md) · [Siguiente página →](00-secreto-sin-echo.md)

En el módulo 5 la aplicación dice la clave en voz alta para que veas que llegó. Esa misma frase es el fallo que un test de integración tiene que cazar: el valor queda en el log. Aquí la prueba demuestra que la integración funciona y la salida no lleva el secreto.

## Qué aprenderás

- Dejar el secreto en un fichero de modo `600` con Vault Agent, y afirmar una huella en vez del valor.
- Entregar el `secret_id` dentro de un envoltorio de un solo uso, y ver que un echo de ese token no sirve para entrar.
- Firmar con el motor Transit a través del proxy de Agent, sin que la app reciba la clave privada ni el token.
- Ejecutar las tres afirmaciones en una batería que escribe `PASS` o `FAIL`.

## Teoría

Hay tres entregas. Las tres usan Vault Agent en el contenedor `pagos`, al lado de la aplicación. El servidor sigue siendo `vault-dev`.

| Escenario | La salida enseña | El dato se queda |
|-----------|------------------|------------------|
| Fichero | `huella=` de 12 hexadecimales y `modo=600` | El valor, en `/tmp/clave` |
| Envoltorio | Un login `400` y un segundo unwrap `400` | El `secret_id`, abierto una vez por Agent |
| Firma | `firma_prefijo=vault:v1:` y `valida=true` | La clave privada, dentro de Transit |

En Vault 1.18 un bloque `exec` exige al menos un `env_template`, y un `template` de fichero no puede ir en el mismo `agent.hcl` que un `env_template`. El `exec` del módulo 5 mete la clave en el entorno del proceso. Aquí Agent queda en marcha, escribe el fichero y el proceso de negocio se arranca aparte.

```text
fichero                         envoltorio                      firma
vault agent                     vault agent                     vault agent
  template → /tmp/clave 0600      unwrap del wrapping token       proxy 127.0.0.1:8100
negocio.sh lee el fichero       el secret_id no se imprime      firmar.sh pide la firma
imprime la huella               el token de entrega ya no vale   imprime vault:v1:
```

El envoltorio es response wrapping. `vault write -wrap-ttl` devuelve un wrapping token. Ese token no es un `secret_id`: el login con él responde `invalid role or secret ID`. Agent, con `secret_id_response_wrapping_path`, lo abre una vez. El segundo `vault unwrap` responde `wrapping token is not valid or does not exist`.

La firma usa el motor `transit`. La app manda el texto `pago:42` al proxy local. Agent añade su token. Transit devuelve `vault:v1:…` y `transit/verify` dice `valid: true`. Leer `transit/export/signing-key/pagos` con el token `root` responde `private key material is not exportable`: la clave privada no tiene un sitio por donde salir, ni hacia el echo ni hacia la API.

> [!NOTE]
> El log de Agent, al arrancar el proxy, avisa de que esa función pasa al subcomando `vault proxy`. En este módulo el proceso sigue siendo `vault agent`.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [El secreto no sale por el echo](00-secreto-sin-echo.md) | Fichero, envoltorio y firma, en un mismo servidor |
| 01 | [La huella en el fichero](01-lab-huella-en-fichero.md) | La huella cambia al rotar y el valor no aparece |
| 02 | [secret_id envuelto](02-lab-secret-id-envuelto.md) | El token de entrega no entra, y Agent lo gasta |
| 03 | [La app firma](03-lab-firma-transit.md) | `vault:v1:` y la clave privada no se exporta |
| 04 | [La batería](04-lab-bateria.md) | Tres `PASS` en una sola ejecución |

→ Empieza por **[00 — El secreto no sale por el echo](00-secreto-sin-echo.md)**.
