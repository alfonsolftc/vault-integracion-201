# M05 — Integración con aplicaciones

[← Página anterior](../M04-autenticacion/03-lab-secret-id-un-uso.md) · [Siguiente página →](00-integrar-aplicacion.md)

El Departamento de Test no administra el clúster: comprueba que una aplicación consigue el secreto y lo usa. Hay dos integraciones distintas, y las dos se ven en un script.

## Qué aprenderás

- Una app cuyo código llama a la API de Vault, hace login y usa la clave.
- Un proceso de negocio que no menciona Vault: solo lee la variable `CLAVE`.
- Un inyector (el papel de un job de CI o de un entrypoint) que habla con Vault, exporta `CLAVE` y ejecuta ese proceso.
- Vault Agent como ese mismo entrypoint: `env_template` rellena `CLAVE` y `exec` arranca el proceso.
- Por qué el contenedor `pagos` usa la imagen de Vault, y por qué el proceso de negocio no usa ese cliente.
- Un job que sale con un código distinto si faltan credenciales o si el login es 400.
- Una app que entra en Postgres con un usuario que Vault crea al momento.

## Teoría

Hay dos sitios. `vault-dev` es el servidor. La aplicación vive en otro: tu terminal, o el contenedor `pagos`.

Hay dos maneras de entregarle la clave.

| | Quién llama a Vault | Qué hace el proceso de negocio |
|--|---------------------|--------------------------------|
| Código integrado | El propio código de la app | Login, GET y uso de la clave, en el mismo script |
| Inyección | Otro proceso: un job, un entrypoint o Vault Agent | Lee `$CLAVE` y trabaja. Su código no cambia |

```text
código integrado                         inyección
app-pagos.sh                             inyector.sh  o  vault agent
    |  login y GET                           |  login y GET
    +------------------> vault-dev           +------------------> vault-dev
    |  usa la clave                          |  export CLAVE=...
    |                                        |  exec negocio.sh
    |                                        negocio.sh solo lee $CLAVE
```

Vault Agent es el binario `vault` con el subcomando `agent`. Corre en la máquina de la aplicación. Con `auto_auth` hace el login, con `env_template` mete el secreto en una variable y con `exec` arranca el proceso de negocio. Ese proceso hereda el entorno y no recibe un token.

El contenedor `pagos` es esa máquina, en la red de `vault-dev`. La imagen es `hashicorp/vault` porque incluye el binario `vault`: hace falta para ejecutar Agent. El proceso de negocio es un `sh` que lee `$CLAVE` y no llama a ese binario. `sleep` solo mantiene el contenedor encendido mientras se copian los ficheros. En un despliegue, el comando del contenedor sería `vault agent -config=…` y ese proceso sería el entrypoint.

`agent.hcl` es lo único que se le da a Agent:

| Bloque | Para qué está |
|--------|----------------|
| `pid_file` | Dónde escribe su número de proceso, para poder pararlo |
| `vault.address` | Dónde está el servidor visto desde `pagos`: `http://vault-dev:8200`. Ahí `127.0.0.1` es el propio contenedor |
| `auto_auth` | El login AppRole. Lee `role_id` y `secret_id` de fichero |
| `remove_secret_id_file_after_reading` | Con `false`, el fichero sigue y Agent puede arrancar otra vez |
| `env_template "CLAVE"` | El GET del secreto. El valor queda en la variable `CLAVE` del proceso hijo |
| `exec` | El entrypoint: cuando `CLAVE` está lista, arranca `/bin/sh /tmp/negocio.sh` |

La tercera entrega usa el motor `database`. La app pide un usuario de Postgres y Vault lo crea con un lease. El mismo motor tiene plugins para MySQL o Redis; aquí Postgres basta para ver el usuario entrar y leer una fila.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [Integrar una aplicación](00-integrar-aplicacion.md) | Código que llama a la API, inyector y Agent como entrypoint |
| 01 | [Consumo automático](01-lab-consumo-automatico.md) | Los tres, desde un servidor vacío |
| 02 | [El job que falla cerrado](02-lab-job-falla-cerrado.md) | El inyector de CI sale 2 sin credenciales y 1 si el login es 400 |
| 03 | [Agent y el cambio en caliente](03-lab-agent-en-caliente.md) | Agent mata el proceso y lo vuelve a ejecutar con la clave nueva |
| 04 | [La app entra en Postgres](04-lab-credencial-de-postgres.md) | Cada arranque recibe un usuario distinto, y al revocar deja de existir |

→ Empieza por **[00 — Integrar una aplicación](00-integrar-aplicacion.md)**.
